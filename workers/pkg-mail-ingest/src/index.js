// Cloudflare Email Worker: push each package email into Stalwart over JMAP.
// The Worker does not parse the message. It streams the raw bytes (message.raw) to Stalwart.
// If anything fails, the Worker forwards the message to FALLBACK_ADDR so no email is lost.

export default {
  async email(message, env) {
    try {
      const auth = {
        authorization: "Basic " + btoa(`${env.STALWART_USER}:${env.STALWART_PASSWORD}`),
        "cf-access-client-id": env.CF_ACCESS_CLIENT_ID,
        "cf-access-client-secret": env.CF_ACCESS_CLIENT_SECRET,
      };

      // content-length is required. A chunked upload (unknown length) can be rejected by Stalwart.
      const upload = await fetch(`${env.JMAP_URL}/jmap/upload/${env.ACCOUNT_ID}/`, {
        method: "POST",
        headers: {
          ...auth,
          "content-type": "message/rfc822",
          "content-length": String(message.rawSize),
        },
        body: message.raw,
      });
      if (!upload.ok) throw new Error(`upload failed: ${upload.status} ${await upload.text()}`);
      const { blobId } = await upload.json();

      const jmap = await fetch(`${env.JMAP_URL}/jmap/`, {
        method: "POST",
        headers: { ...auth, "content-type": "application/json" },
        body: JSON.stringify({
          using: ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
          methodCalls: [
            [
              "Email/import",
              {
                accountId: env.ACCOUNT_ID,
                emails: {
                  m: {
                    blobId,
                    mailboxIds: { [env.INBOX_ID]: true },
                    receivedAt: new Date().toISOString(),
                  },
                },
              },
              "0",
            ],
          ],
        }),
      });
      if (!jmap.ok) throw new Error(`import failed: ${jmap.status} ${await jmap.text()}`);

      // JMAP returns 200 even when one item fails, so check the method response.
      const [name, result] = (await jmap.json()).methodResponses[0];
      if (name !== "Email/import" || !result.created?.m) {
        throw new Error(`import not created: ${JSON.stringify(result.notCreated ?? result)}`);
      }
    } catch (err) {
      console.error("pkg-mail-ingest failed, forwarding to fallback:", err);
      await message.forward(env.FALLBACK_ADDR);
    }
  },
};

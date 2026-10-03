const functions = require("firebase-functions");
const admin = require("firebase-admin");
const fetch = require("node-fetch");

admin.initializeApp();
const db = admin.firestore();

async function verifyUser(req) {
  const authHeader = req.headers.authorization || "";
  const match = authHeader.match(/^Bearer (.+)$/);
  if (!match) throw new Error("UNAUTHENTICATED");

  const decoded = await admin.auth().verifyIdToken(match[1]);
  const userDoc = await db.collection("users").doc(decoded.uid).get();
  if (!userDoc.exists) throw new Error("USER_NOT_FOUND");

  const userData = userDoc.data();
  return {
    uid: decoded.uid,
    role: userData.role || "user",       
    installationId: userData.installationId,
  };
}

async function getOpenHABConfig(installationId) {
  const doc = await db.collection("installations").doc(installationId).get();
  if (!doc.exists) throw new Error("INSTALLATION_NOT_FOUND");
  return doc.data();
}

function buildOpenHABHeaders(config) {
  const headers = { Accept: "application/json" };
  if (config.openhabToken) {
    headers.Authorization = `Bearer ${config.openhabToken}`;
  } else if (config.openhabUsername && config.openhabPassword) {
    const encoded = Buffer.from(
      `${config.openhabUsername}:${config.openhabPassword}`
    ).toString("base64");
    headers.Authorization = `Basic ${encoded}`;
  }
  return headers;
}

exports.getThings = functions.https.onRequest(async (req, res) => {
  try {
    const user = await verifyUser(req);
    const config = await getOpenHABConfig(user.installationId);

    const r = await fetch(`${config.openhabUrl}/rest/things`, {
      headers: buildOpenHABHeaders(config),
    });
    const data = await r.json();
    res.status(200).json(data);
  } catch (e) {
    handleError(res, e);
  }
});

exports.sendItemCommand = functions.https.onRequest(async (req, res) => {
  try {
    if (req.method !== "POST") throw new Error("METHOD_NOT_ALLOWED");
    const user = await verifyUser(req);
    const config = await getOpenHABConfig(user.installationId);

    const itemName = req.query.itemName;
    const command = req.body.command;
    if (!itemName || !command) throw new Error("BAD_REQUEST");

    const r = await fetch(`${config.openhabUrl}/rest/items/${itemName}`, {
      method: "POST",
      headers: {
        ...buildOpenHABHeaders(config),
        "Content-Type": "text/plain",
      },
      body: command,
    });

    await db.collection("auditLogs").add({
      uid: user.uid,
      role: user.role,
      action: "sendCommand",
      itemName,
      command,
      installationId: user.installationId,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.status(r.ok ? 200 : 502).json({ ok: r.ok });
  } catch (e) {
    handleError(res, e);
  }
});

exports.addThing = functions.https.onRequest(async (req, res) => {
  try {
    if (req.method !== "POST") throw new Error("METHOD_NOT_ALLOWED");
    const user = await verifyUser(req);

    if (user.role !== "admin") throw new Error("FORBIDDEN");

    const config = await getOpenHABConfig(user.installationId);
    const r = await fetch(`${config.openhabUrl}/rest/things`, {
      method: "POST",
      headers: {
        ...buildOpenHABHeaders(config),
        "Content-Type": "application/json",
      },
      body: JSON.stringify(req.body),
    });
    const data = await r.json().catch(() => ({}));

    await db.collection("auditLogs").add({
      uid: user.uid,
      role: user.role,
      action: "addThing",
      payload: req.body,
      installationId: user.installationId,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.status(r.status).json(data);
  } catch (e) {
    handleError(res, e);
  }
});

exports.updateServerConfig = functions.https.onRequest(async (req, res) => {
  try {
    if (req.method !== "PUT") throw new Error("METHOD_NOT_ALLOWED");
    const user = await verifyUser(req);
    if (user.role !== "admin") throw new Error("FORBIDDEN");

    const { openhabUrl, openhabToken, openhabUsername, openhabPassword } =
      req.body;
    if (!openhabUrl) throw new Error("BAD_REQUEST");

    await db.collection("installations").doc(user.installationId).set(
      {
        openhabUrl,
        ...(openhabToken ? { openhabToken } : {}),
        ...(openhabUsername ? { openhabUsername } : {}),
        ...(openhabPassword ? { openhabPassword } : {}),
      },
      { merge: true }
    );

    res.status(200).json({ ok: true });
  } catch (e) {
    handleError(res, e);
  }
});

function handleError(res, e) {
  const map = {
    UNAUTHENTICATED: 401,
    USER_NOT_FOUND: 401,
    FORBIDDEN: 403,
    INSTALLATION_NOT_FOUND: 404,
    BAD_REQUEST: 400,
    METHOD_NOT_ALLOWED: 405,
  };
  const status = map[e.message] || 500;
  res.status(status).json({ error: e.message || "INTERNAL_ERROR" });
}
const { onSchedule } = require("firebase-functions/v2/scheduler");
const functions = require("firebase-functions");
const { onObjectFinalized } = require("firebase-functions/v2/storage");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, writeBatch, Timestamp } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const { GoogleGenerativeAI } = require("@google/generative-ai");

initializeApp();

// ======================================================
// 1) SCHEDULED EXPIRY CHECK
// ======================================================
exports.checkGeminiAttractionExpiry = onSchedule("every 24 hours", async () => {
  const db = getFirestore();
  const now = new Date();

  const snapshot = await db
    .collection("attractions")
    .where("expiryDate", "<=", Timestamp.fromDate(now))
    .where("expired", "==", false)
    .get();

  if (snapshot.empty) return null;

  const batch = writeBatch(db);
  snapshot.forEach((doc) => {
    batch.update(doc.ref, { expired: true, expiredAt: Timestamp.fromDate(now) });
  });

  await batch.commit();
  return null;
});

// ======================================================
// 2) MANUAL TRIGGER
// ======================================================
exports.runExpiryCheckNow = functions.https.onRequest(async (req, res) => {
  try {
    const db = getFirestore();
    const now = new Date();

    const snapshot = await db
      .collection("attractions")
      .where("expiryDate", "<=", Timestamp.fromDate(now))
      .where("expired", "==", false)
      .get();

    if (snapshot.empty) {
      res.status(200).send("No documents to update");
      return;
    }

    const batch = writeBatch(db);
    snapshot.forEach((doc) => {
      batch.update(doc.ref, { expired: true, expiredAt: Timestamp.fromDate(now) });
    });

    await batch.commit();

    res.status(200).send("Expiry update completed");
  } catch (error) {
    res.status(500).send("Error: " + error.message);
  }
});

// ======================================================
// 3) AI EXPIRY EXTRACTION ON DOCUMENT UPLOAD
// ======================================================
exports.extractExpiryOnUpload = onObjectFinalized(
  {
    bucket: "studio-6313173084-d2ab9.appspot.com",
    location: "us-central1",
    region: "us-central1",
  },
  async (event) => {
    const filePath = event.data.name;

    const parts = filePath.split("/");
    const docId = parts[1];

    if (!docId) return;

    const bucket = getStorage().bucket(event.data.bucket);
    const file = bucket.file(filePath);
    const [buffer] = await file.download();

    const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
    const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" });

    const result = await model.generateContent([
      {
        inlineData: {
          data: buffer.toString("base64"),
          mimeType: event.data.contentType,
        },
      },
      "Extract the expiry date from this document. Return only ISO date (YYYY-MM-DD).",
    ]);

    const expiryText = result.response.text().trim();
    const expiryDate = new Date(expiryText);

    const db = getFirestore();
    await db.collection("attractions").doc(docId).update({
      expiryDate: Timestamp.fromDate(expiryDate),
      expired: false,
      updatedAt: Timestamp.now(),
    });
  }
);

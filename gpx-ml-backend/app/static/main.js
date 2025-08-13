// static/main.js

// ====== CONFIG (matches dashboardv14.html) ======
const EXPLORER_BASE = "https://holesky.etherscan.io";

// Contract to log activity (with logActivity function)
const ACTIVITY_LOGGER_ADDRESS = "0x26E24bfe2A21515eb91Cea4b754FA56067bC70cB";
// Minimal ABI for logActivity + (optional) event
const ACTIVITY_LOGGER_ABI = [
  "function logActivity(uint256 distanceKmX100, uint256 elevationGainM, uint256 activityTimestamp) external",
  "event ActivityLogged(address indexed user, uint256 distanceKmX100, uint256 elevationGainM, uint256 timestamp)"
];

// ====== DOM HELPERS ======
const $ = (sel) => document.querySelector(sel);

function setMLResult(html) {
  const el = $("#mlResult");
  if (el) el.innerHTML = html;
}

function formatFeatures(f) {
  if (!f) return "-";
  return `
    <ul style="margin:8px 0 0 18px; padding:0;">
      <li><b>Distance (km):</b> ${f.total_distance_km}</li>
      <li><b>Duration (min):</b> ${f.duration_minutes}</li>
      <li><b>Avg speed (km/h):</b> ${f.avg_speed_kmh}</li>
      <li><b>Elevation gain (m):</b> ${f.elevation_gain_m}</li>
      <li><b>Timestamp:</b> ${f.activity_timestamp}</li>
    </ul>
  `;
}

// ====== ETHERS HELPERS ======
async function getProviderAndSigner() {
  if (!window.ethereum) {
    throw new Error("Please install MetaMask to continue.");
  }
  const provider = new ethers.providers.Web3Provider(window.ethereum);
  await provider.send("eth_requestAccounts", []);
  const signer = provider.getSigner();
  const user = await signer.getAddress();
  return { provider, signer, user };
}

function getActivityLoggerContract(signerOrProvider) {
  return new ethers.Contract(ACTIVITY_LOGGER_ADDRESS, ACTIVITY_LOGGER_ABI, signerOrProvider);
}

// ====== BACKEND ↔ FRONTEND FLOW ======
async function verifyWorkout() {
  try {
    setMLResult("⏳ Uploading file and running ML verification...");
    const fileInput = $("#gpxFileInput");
    if (!fileInput || !fileInput.files || fileInput.files.length === 0) {
      throw new Error("Please select a .gpx file first.");
    }
    const gpxFile = fileInput.files[0];
    if (!gpxFile.name.toLowerCase().endsWith(".gpx")) {
      throw new Error("File is not a .gpx format.");
    }

    // Get user address from MetaMask to send along with the backend request
    const { signer, user } = await getProviderAndSigner();

    // Call FastAPI: /upload-workout
    const fd = new FormData();
    fd.append("file", gpxFile);
    fd.append("user_address", user);

    const res = await fetch("/upload-workout", {
      method: "POST",
      body: fd,
    });

    if (!res.ok) {
      const msg = await res.text();
      throw new Error(`Backend error: ${msg || res.status}`);
    }

    const data = await res.json();
    const { result, features } = data || {};
    const isReal = String(result).toUpperCase() === "REAL";

    setMLResult(`
      ✅ ML Result: <b>${isReal ? "REAL" : "FAKE"}</b>
      ${formatFeatures(features)}
    `);

    // If FAKE, stop here
    if (!isReal) {
      setMLResult(`
        ❌ Activity classified as <b>FAKE</b>. Not logging on blockchain.
        ${formatFeatures(features)}
      `);
      return;
    }

    // If REAL ⇒ call smart contract logActivity
    const txInfo = await sendRecordToContract(features);
    const shortHash = `${txInfo.hash.slice(0, 6)}...${txInfo.hash.slice(-4)}`;
    const txUrl = `${EXPLORER_BASE}/tx/${txInfo.hash}`;

    setMLResult(`
      ✅ ML: <b>REAL</b> — activity logged on blockchain.<br/>
      🔗 TX: <a href="${txUrl}" target="_blank">${shortHash}</a>
      ${formatFeatures(features)}
    `);

    // Optional: refresh on-chain dashboard after logging
    if (typeof window.loadDashboardData === "function") {
      try { await window.loadDashboardData(); } catch (_) {}
    }

  } catch (err) {
    console.error(err);
    setMLResult(`⚠️ Error: ${err.message || err}`);
  }
}

// ====== FRONTEND ↔ SMART CONTRACT ======
async function sendRecordToContract(features) {
  if (!features) throw new Error("Missing features to log on-chain.");

  // Convert units:
  // - Contract expects distanceKmX100 (km * 100, uint), NOT meters.
  // - elevationGainM is integer meters.
  // - activityTimestamp is Unix epoch (seconds).
  const distanceKm = Number(features.total_distance_km || 0); // e.g., 5.23
  const distanceKmX100 = Math.round(distanceKm * 100);        // 523
  const elevationGainM = Math.round(Number(features.elevation_gain_m || 0));
  const activityTimestamp = Number(features.activity_timestamp || 0);

  if (distanceKmX100 < 0 || elevationGainM < 0 || activityTimestamp <= 0) {
    throw new Error("Invalid feature values for on-chain logging.");
  }

  const { signer, user } = await getProviderAndSigner();
  const contract = getActivityLoggerContract(signer);

  // Send transaction
  const tx = await contract.logActivity(
    ethers.BigNumber.from(distanceKmX100),
    ethers.BigNumber.from(elevationGainM),
    ethers.BigNumber.from(activityTimestamp)
  );

  // Wait until mined
  const receipt = await tx.wait();
  return { hash: tx.hash, receipt };
}

// ====== EXPORT TO GLOBAL (for HTML to call) ======
window.verifyWorkout = verifyWorkout;
window.sendRecordToContract = sendRecordToContract;

const dropzone = document.getElementById("dropzone");
const fileInput = document.getElementById("file-input");
const dropzoneText = document.getElementById("dropzone-text");
const dropzoneFilename = document.getElementById("dropzone-filename");
const form = document.getElementById("upload-form");
const generateBtn = document.getElementById("generate-btn");
const progressBox = document.getElementById("progress-box");
const progressFill = document.getElementById("progress-fill");
const progressText = document.getElementById("progress-text");
const resultBox = document.getElementById("result-box");
const libraryList = document.getElementById("library-list");
const langSelect = document.getElementById("lang-select");
const voiceSelect = document.getElementById("voice-select");

let selectedFile = null;
let voiceCatalog = {};

async function loadVoices() {
  const res = await fetch("/api/voices");
  const data = await res.json();
  voiceCatalog = data.voices;
  for (const [code, name] of Object.entries(data.languages)) {
    const opt = document.createElement("option");
    opt.value = code;
    opt.textContent = name;
    langSelect.appendChild(opt);
  }
}

function updateVoiceOptions() {
  const lang = langSelect.value;
  voiceSelect.innerHTML = "";
  if (lang === "auto") {
    voiceSelect.disabled = true;
    voiceSelect.innerHTML = `<option value="">(auto)</option>`;
    return;
  }
  voiceSelect.disabled = false;
  const defaultOpt = document.createElement("option");
  defaultOpt.value = "";
  defaultOpt.textContent = "(voz por defecto)";
  voiceSelect.appendChild(defaultOpt);
  for (const voice of voiceCatalog[lang] || []) {
    const opt = document.createElement("option");
    opt.value = voice.id;
    opt.textContent = voice.label;
    voiceSelect.appendChild(opt);
  }
}

langSelect.addEventListener("change", updateVoiceOptions);
loadVoices();

async function loadServerInfo() {
  const res = await fetch("/api/server-info");
  const { phone_url, library_dir } = await res.json();
  if (phone_url) {
    document.getElementById("phone-url-value").textContent = phone_url;
    document.getElementById("phone-url").classList.remove("hidden");
  }
  if (library_dir) {
    document.getElementById("library-dir").textContent = library_dir;
    document.getElementById("library-hint").classList.remove("hidden");
  }
}
loadServerInfo();

dropzone.addEventListener("click", () => fileInput.click());
dropzone.addEventListener("dragover", (e) => { e.preventDefault(); dropzone.classList.add("dragover"); });
dropzone.addEventListener("dragleave", () => dropzone.classList.remove("dragover"));
dropzone.addEventListener("drop", (e) => {
  e.preventDefault();
  dropzone.classList.remove("dragover");
  if (e.dataTransfer.files.length) {
    selectedFile = e.dataTransfer.files[0];
    showSelectedFile();
  }
});
fileInput.addEventListener("change", () => {
  if (fileInput.files.length) {
    selectedFile = fileInput.files[0];
    showSelectedFile();
  }
});

function showSelectedFile() {
  dropzoneText.textContent = "Archivo elegido:";
  dropzoneFilename.textContent = selectedFile.name;
}

form.addEventListener("submit", async (e) => {
  e.preventDefault();
  if (!selectedFile) {
    alert("Elegi un archivo primero.");
    return;
  }

  const lang = langSelect.value;
  const voice = voiceSelect.value;
  const formData = new FormData();
  formData.append("file", selectedFile);
  formData.append("lang", lang);
  formData.append("voice", voice);

  generateBtn.disabled = true;
  resultBox.classList.add("hidden");
  resultBox.classList.remove("error");
  progressBox.classList.remove("hidden");
  progressFill.style.width = "0%";
  progressText.textContent = "Subiendo archivo...";

  try {
    const res = await fetch("/api/generate", { method: "POST", body: formData });
    if (!res.ok) {
      const err = await res.json();
      throw new Error(err.detail || "Error al iniciar la generacion");
    }
    const { job_id } = await res.json();
    pollJob(job_id);
  } catch (err) {
    showError(err.message);
    generateBtn.disabled = false;
  }
});

function pollJob(jobId) {
  const interval = setInterval(async () => {
    try {
      const res = await fetch(`/api/jobs/${jobId}`);
      const job = await res.json();

      const pct = job.total ? Math.round((job.step / job.total) * 100) : 0;
      progressFill.style.width = `${pct}%`;
      progressText.textContent = job.stage || job.status;

      if (job.status === "done") {
        clearInterval(interval);
        generateBtn.disabled = false;
        showSuccess(jobId);
        loadLibrary();
      } else if (job.status === "error") {
        clearInterval(interval);
        generateBtn.disabled = false;
        showError(job.error || "Fallo la generacion");
      }
    } catch (err) {
      clearInterval(interval);
      generateBtn.disabled = false;
      showError("Se perdio la conexion con el servidor");
    }
  }, 1000);
}

function showSuccess(jobId) {
  resultBox.classList.remove("hidden", "error");
  resultBox.innerHTML = `Audiolibro listo. <a href="/api/jobs/${jobId}/download">Descargar M4B</a>`;
}

function showError(message) {
  resultBox.classList.remove("hidden");
  resultBox.classList.add("error");
  resultBox.textContent = `Error: ${message}`;
}

async function loadLibrary() {
  const res = await fetch("/api/library");
  const books = await res.json();
  libraryList.innerHTML = "";
  if (!books.length) {
    libraryList.innerHTML = `<li class="empty">Todavia no generaste ningun audiolibro.</li>`;
    return;
  }
  for (const book of books) {
    const li = document.createElement("li");
    const info = document.createElement("span");
    info.append(book.title, document.createElement("br"));
    const meta = document.createElement("span");
    meta.className = "meta";
    meta.textContent = `${book.size_mb} MB · ${book.chapters_count} capitulos`;
    info.append(meta);
    const link = document.createElement("a");
    link.href = book.download_url;
    link.download = book.name;
    link.textContent = "Descargar";
    li.append(info, link);
    libraryList.appendChild(li);
  }
}

loadLibrary();

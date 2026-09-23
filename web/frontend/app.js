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

let selectedFile = null;

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

  const lang = document.getElementById("lang-select").value;
  const formData = new FormData();
  formData.append("file", selectedFile);
  formData.append("lang", lang);

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
    li.innerHTML = `
      <span>${book.name}<br><span class="meta">${book.size_mb} MB</span></span>
      <a href="${book.download_url}" download>Descargar</a>
    `;
    libraryList.appendChild(li);
  }
}

loadLibrary();

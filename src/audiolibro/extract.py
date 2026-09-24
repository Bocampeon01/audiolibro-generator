"""Extraccion de texto plano desde PDF, DOCX o TXT."""
from pathlib import Path


def extract_text(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix == ".txt":
        return _decode_txt(path.read_bytes())
    if suffix == ".pdf":
        return _extract_pdf(path)
    if suffix in (".docx",):
        return _extract_docx(path)
    raise ValueError(f"Formato no soportado: {suffix}")


def _decode_txt(data: bytes) -> str:
    # Bloc de notas de Windows guarda en UTF-8 (con o sin BOM), UTF-16 ("Unicode")
    # o ANSI/cp1252. Decodificar cp1252 como utf-8 con errors=ignore borra los acentos.
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        return data.decode("utf-16")
    try:
        return data.decode("utf-8-sig")
    except UnicodeDecodeError:
        return data.decode("cp1252", errors="replace")


def _extract_pdf(path: Path) -> str:
    from pypdf import PdfReader

    reader = PdfReader(str(path))
    pages = [page.extract_text() or "" for page in reader.pages]
    text = "\n\n".join(pages)
    if not text.strip():
        raise ValueError(
            "No se pudo extraer texto del PDF (probablemente escaneado). "
            "OCR todavia no esta implementado."
        )
    return text


def _extract_docx(path: Path) -> str:
    import docx

    doc = docx.Document(str(path))
    return "\n\n".join(p.text for p in doc.paragraphs if p.text.strip())

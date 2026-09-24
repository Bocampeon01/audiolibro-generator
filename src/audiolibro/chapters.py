"""Segmentacion de texto en capitulos."""
import re
import unicodedata
from dataclasses import dataclass

# Numero arabigo seguido de cualquier cosa ("Capitulo 3 El regreso"), o romano seguido
# de fin de linea / separador ("Chapter IV: ..."). Con romanos no se acepta otra palabra
# despues: "Parte di questa storia" (it) usa letras que parecen romanos.
CHAPTER_PATTERN = re.compile(
    r"^\s*(cap[ií]tulo|chapter|parte|part|chapitre|capitolo|kapitel)\s+"
    r"(?:[0-9]+\b|[ivxlcdm]+(?=\s*$|\s*[.:\-—–]))",
    re.IGNORECASE,
)

MAX_CHUNK_CHARS = 12000  # fallback si no hay capitulos detectables
MAX_HEADING_CHARS = 80  # "Parte di questa storia..." (it) no es un titulo: es una oracion

# "Capitulo primero", "Chapter Twenty-One", "Chapitre dix-sept": numeros en palabras.
# Lista cerrada (sin acentos, minuscula) en vez de "palabra cualquiera": en PDFs hay lineas
# cortadas tipo "parte de la historia" que no son titulos.
_KEYWORD = re.compile(r"^\s*(cap[ií]tulo|chapter|parte|part|chapitre|capitolo|kapitel)\s+(.+)$", re.IGNORECASE)
_TITLE_SEPARATOR = re.compile(r"\s*[.:—–]\s*|\s+-\s+")
_CONNECTORS = {"y", "e", "and"}
NUMBER_WORDS = _CONNECTORS | set("""
    uno una dos tres cuatro cinco seis siete ocho nueve diez once doce trece catorce quince
    dieciseis diecisiete dieciocho diecinueve veinte veintiuno veintiun veintidos veintitres
    veinticuatro veinticinco veintiseis veintisiete veintiocho veintinueve treinta cuarenta cincuenta
    primero primer segundo tercero tercer cuarto quinto sexto septimo setimo octavo noveno decimo
    undecimo duodecimo decimoprimero decimosegundo decimotercero decimocuarto decimoquinto
    vigesimo trigesimo ultimo
    primera segunda tercera cuarta quinta sexta septima setima octava novena decima ultima
    one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen
    sixteen seventeen eighteen nineteen twenty thirty forty fifty first second third fourth fifth
    sixth seventh eighth ninth tenth eleventh twelfth thirteenth fourteenth fifteenth twentieth last
    um dois duas quatro sete oito nove dez onze doze treze catorze quatorze quinze dezesseis
    dezessete dezoito dezenove vinte trinta primeiro terceiro oitavo nono
    primeira terceira oitava nona
    un deux trois quatre cinq sept huit neuf dix seize vingt trente premier premiere deuxieme
    troisieme quatrieme cinquieme sixieme septieme huitieme neuvieme dixieme dernier
    due quattro sei sette otto dieci undici dodici tredici quattordici sedici diciassette diciotto
    diciannove venti primo terzo sesto settimo ottavo
    prima seconda terza quarta sesta settima ottava nona
    eins zwei drei vier funf fuenf sechs sieben acht neun zehn elf zwolf zwoelf zwanzig dreissig
    erstes erster zweites drittes viertes funftes sechstes siebtes achtes neuntes zehntes
""".split())


@dataclass
class Chapter:
    title: str
    text: str


def _plain(text: str) -> str:
    text = unicodedata.normalize("NFKD", text.lower())
    return "".join(ch for ch in text if not unicodedata.combining(ch)).replace("ß", "ss")


def _is_word_number_heading(line: str) -> bool:
    m = _KEYWORD.match(line)
    if not m:
        return False
    # El titulo solo puede seguir tras un separador: "Capitulo primero: El inicio".
    number = _TITLE_SEPARATOR.split(m.group(2), maxsplit=1)[0]
    tokens = _plain(number).replace("-", " ").split()
    return (
        1 <= len(tokens) <= 4
        and tokens[0] not in _CONNECTORS
        and all(t in NUMBER_WORDS for t in tokens)
    )


def _is_heading(line: str) -> bool:
    if len(line.strip()) > MAX_HEADING_CHARS:
        return False
    return bool(CHAPTER_PATTERN.match(line)) or _is_word_number_heading(line)


def split_into_chapters(text: str) -> list[Chapter]:
    lines = text.splitlines()
    matches = [i for i, line in enumerate(lines) if _is_heading(line)]

    if matches:
        chapters = []
        preface = "\n".join(lines[: matches[0]]).strip()
        if preface:
            chapters.append(Chapter(title="Inicio", text=preface))
        for idx, start in enumerate(matches):
            end = matches[idx + 1] if idx + 1 < len(matches) else len(lines)
            title = lines[start].strip()
            body = "\n".join(lines[start + 1 : end]).strip()
            if body:
                chapters.append(Chapter(title=title, text=body))
        if chapters:
            return chapters

    return _split_by_length(text)


def _split_by_length(text: str) -> list[Chapter]:
    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
    chunks: list[Chapter] = []
    current = []
    current_len = 0
    for para in paragraphs:
        if current_len + len(para) > MAX_CHUNK_CHARS and current:
            chunks.append(Chapter(title=f"Parte {len(chunks) + 1}", text="\n\n".join(current)))
            current = []
            current_len = 0
        current.append(para)
        current_len += len(para)
    if current:
        chunks.append(Chapter(title=f"Parte {len(chunks) + 1}", text="\n\n".join(current)))
    return chunks

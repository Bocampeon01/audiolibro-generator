from audiolibro import chapters, extract, sentences
from audiolibro.build_m4b import _ffmeta_escape


# --- sentences ---------------------------------------------------------------

def test_long_clause_without_commas_terminates_and_keeps_comma():
    text = "a" * 250 + ", " + "b " * 200
    parts = sentences._cap_length(text.strip())
    assert all(len(p) <= sentences.MAX_SENTENCE_CHARS for p in parts)
    assert parts[0].endswith(",")
    assert not any(p.startswith(",") for p in parts)
    assert "".join(parts).replace(" ", "") == text.replace(" ", "")


def test_pdf_line_wraps_are_joined():
    text = "El perro corria por el\ncampo verde y la gente\nmiraba asombrada. Fin."
    assert sentences.split_into_sentences(text) == [
        "El perro corria por el campo verde y la gente miraba asombrada.",
        "Fin.",
    ]


def test_hyphenated_line_wrap_is_rejoined():
    assert sentences.split_into_sentences("Una pala-\nbra cortada.") == ["Una palabra cortada."]


def test_blank_line_separates_paragraphs():
    assert sentences.split_into_sentences("Titulo sin punto\n\nPrimera oracion.") == [
        "Titulo sin punto",
        "Primera oracion.",
    ]


def test_unspeakable_chunks_are_dropped():
    # Piper no produce audio para estos: antes tiraban abajo toda la generacion.
    assert sentences.split_into_sentences("Hola.\n\n—\n\n...\n\n* * *\n\nChau.") == ["Hola.", "Chau."]


def test_splits_before_dialogue_dash_and_quotes():
    text = 'Llego tarde. —Perdon —dijo. "Nada" respondio. 3 dias despues.'
    assert sentences.split_into_sentences(text) == [
        "Llego tarde.",
        "—Perdon —dijo.",
        '"Nada" respondio.',
        "3 dias despues.",
    ]


# --- chapters ----------------------------------------------------------------

def test_text_before_first_chapter_is_kept():
    chs = chapters.split_into_chapters("Prologo importante.\n\nCapitulo 1\n\nTexto del uno.")
    assert [(c.title, c.text) for c in chs] == [
        ("Inicio", "Prologo importante."),
        ("Capitulo 1", "Texto del uno."),
    ]


def test_italian_sentence_is_not_a_chapter_heading():
    text = "Capitolo 1\n\nParte di questa storia e vera, anche se nessuno ci crede davvero, mai."
    chs = chapters.split_into_chapters(text)
    assert [c.title for c in chs] == ["Capitolo 1"]


def test_headings_in_all_languages():
    for heading in [
        "Capítulo 3", "Chapter IV", "Chapter IV: The Return", "Chapitre 2", "Capitolo 5",
        "Kapitel 1", "Parte II", "Capítulo 7 El regreso",
    ]:
        assert chapters._is_heading(heading), heading


def test_prose_is_not_a_heading():
    for line in [
        "Parte di questa storia", "Part civil war story", "Chapter mix of things",
        "Parte de la historia", "Chapter one of many things", "Parte y", "parte de la gente que",
    ]:
        assert not chapters._is_heading(line), line


def test_headings_with_numbers_in_words():
    for heading in [
        "Capítulo primero", "CAPÍTULO VIGÉSIMO PRIMERO", "Capítulo treinta y uno",
        "Chapter Twenty-One", "Chapter One: The Start", "Chapitre dix-sept",
        "Capitolo terzo", "Kapitel zwei", "Parte segunda — La vuelta",
    ]:
        assert chapters._is_heading(heading), heading


# --- extract -----------------------------------------------------------------

def test_txt_cp1252_keeps_accents(tmp_path):
    f = tmp_path / "a.txt"
    f.write_bytes("Canción de acción".encode("cp1252"))
    assert extract.extract_text(f) == "Canción de acción"


def test_txt_utf8_bom_and_utf16(tmp_path):
    f = tmp_path / "a.txt"
    f.write_bytes("Canción".encode("utf-8-sig"))
    assert extract.extract_text(f) == "Canción"
    f.write_bytes("Canción".encode("utf-16"))
    assert extract.extract_text(f) == "Canción"


# --- ffmetadata --------------------------------------------------------------

def test_ffmetadata_escaping():
    assert _ffmeta_escape("a=b;c#d\\e\nf") == "a\\=b\\;c\\#d\\\\e\\\nf"

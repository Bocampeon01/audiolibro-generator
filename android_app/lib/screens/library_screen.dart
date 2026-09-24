import 'package:flutter/material.dart';

import '../models/audio_formats.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../services/generation_service.dart';
import '../services/library_service.dart';
import '../services/player_controller.dart';
import '../widgets/mini_player.dart';
import 'player_screen.dart';
import 'server_import_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _service = LibraryService();
  List<Book> _books = [];
  bool _loading = true;
  final _gen = GenerationService.instance;
  late int _seenCompleted = _gen.completedCount;

  @override
  void initState() {
    super.initState();
    _gen.addListener(_onGenerationChanged);
    _refresh();
  }

  @override
  void dispose() {
    _gen.removeListener(_onGenerationChanged);
    super.dispose();
  }

  /// Una generacion lanzada desde "Servidor > Generar" termina aunque el usuario
  /// ya no este en esa pantalla: la biblioteca se entera, refresca y avisa.
  void _onGenerationChanged() {
    if (_gen.completedCount == _seenCompleted) return;
    _seenCompleted = _gen.completedCount;
    _refresh();
    final title = _gen.lastCompleted?.title;
    if (title != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Audiolibro generado: $title')));
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final books = await _service.listBooks();
    if (!mounted) return;
    setState(() {
      _books = books;
      _loading = false;
    });
  }

  Future<void> _importFile({bool showAll = false}) async {
    try {
      final book = await _service.importFromPicker(showAll: showAll);
      if (book != null) {
        await _refresh();
      } else if (!showAll && mounted) {
        // Cancelo sin elegir: quizas su archivo no aparecio por el filtro (algun
        // proveedor informa mal el tipo). Se ofrece ver todo, sin forzarlo.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('¿No aparecia tu archivo?'),
            action: SnackBarAction(
              label: 'Ver todos los archivos',
              onPressed: () => _importFile(showAll: true),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _openServerImport() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ServerImportScreen()),
    );
    await _refresh();
  }

  Future<bool> _confirmDelete(Book book) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar audiolibro'),
        content: Text(
          'Se borra "${book.title}" del celular. No se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _deleteBook(Book book) async {
    final player = PlayerController.instance;
    if (player.book?.id == book.id) await player.close();
    await _service.deleteBook(book);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis audiolibros'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _books.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.library_music, size: 64, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text(
                    'Todavia no tenes audiolibros',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Importa un audiolibro (.m4b, .mp3...) o bajalo del servidor',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            )
          : ListenableBuilder(
              listenable: PlayerController.instance,
              builder: (context, _) => ListView.builder(
                // espacio para que los botones flotantes no tapen el ultimo libro
                padding: const EdgeInsets.only(bottom: 170),
                itemCount: _books.length,
                itemBuilder: (context, i) {
                  final book = _books[i];
                  final isCurrent =
                      PlayerController.instance.book?.id == book.id;
                  return Dismissible(
                    key: ValueKey(book.id),
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) => _confirmDelete(book),
                    onDismissed: (_) => _deleteBook(book),
                    child: ListTile(
                      leading: Icon(
                        isCurrent ? Icons.headphones : Icons.menu_book,
                        color: isCurrent
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: Text(book.title),
                      subtitle: Text(
                        '${extensionOf(book.filePath).toUpperCase()} · '
                        '${book.chapters.isEmpty ? 'sin capitulos' : chaptersLabel(book.chapters.length)}',
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PlayerScreen(book: book),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
      bottomNavigationBar: const MiniPlayer(),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Tooltip(
            message:
                'Solo si el celular esta en el mismo WiFi que la PC.\n'
                'Sin esa red, usa "Importar".',
            child: FloatingActionButton.extended(
              heroTag: 'server',
              onPressed: _openServerImport,
              icon: const Icon(Icons.cloud_download),
              label: const Text('Servidor'),
            ),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'import',
            onPressed: _importFile,
            icon: const Icon(Icons.add),
            label: const Text('Importar'),
          ),
        ],
      ),
    );
  }
}

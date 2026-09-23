import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/library_service.dart';
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

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final books = await _service.listBooks();
    setState(() {
      _books = books;
      _loading = false;
    });
  }

  Future<void> _importFile() async {
    try {
      final book = await _service.importFromPicker();
      if (book != null) await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
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

  Future<void> _deleteBook(Book book) async {
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
                      const Text('Todavia no tenes audiolibros', style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 4),
                      const Text(
                        'Importa un .m4b o descargalo del servidor',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _books.length,
                  itemBuilder: (context, i) {
                    final book = _books[i];
                    return Dismissible(
                      key: ValueKey(book.id),
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) => _deleteBook(book),
                      child: ListTile(
                        leading: const Icon(Icons.menu_book),
                        title: Text(book.title),
                        subtitle: Text(
                          book.chapters.isEmpty
                              ? 'Sin capitulos detectados'
                              : '${book.chapters.length} capitulos',
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => PlayerScreen(book: book)),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'server',
            onPressed: _openServerImport,
            icon: const Icon(Icons.cloud_download),
            label: const Text('Servidor'),
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

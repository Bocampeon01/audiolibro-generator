import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/library_service.dart';

class ServerImportScreen extends StatefulWidget {
  const ServerImportScreen({super.key});

  @override
  State<ServerImportScreen> createState() => _ServerImportScreenState();
}

class _ServerImportScreenState extends State<ServerImportScreen> {
  final _service = LibraryService();
  final _urlController = TextEditingController(text: 'http://10.0.2.2:8000');
  List<ServerBook> _books = [];
  String? _error;
  bool _loading = false;
  final Set<String> _downloading = {};

  static const _prefKey = 'server_url';

  @override
  void initState() {
    super.initState();
    _loadSavedUrl();
  }

  Future<void> _loadSavedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved != null) {
      _urlController.text = saved;
    }
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final baseUrl = _urlController.text.trim().replaceAll(RegExp(r'/$'), '');
    try {
      final books = await _service.fetchServerLibrary(baseUrl);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, baseUrl);
      setState(() => _books = books);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _download(ServerBook item) async {
    final baseUrl = _urlController.text.trim().replaceAll(RegExp(r'/$'), '');
    setState(() => _downloading.add(item.name));
    try {
      await _service.downloadFromServer(baseUrl, item);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Descargado: ${item.title}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _downloading.remove(item.name));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Descargar del servidor')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Direccion del servidor web (PC corriendo audiolibro-generator). '
              'En emulador Android usa 10.0.2.2; en celular fisico usa la IP LAN de la PC.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'URL del servidor',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _loading ? null : _search,
                  child: _loading
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Buscar'),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ),
            const SizedBox(height: 16),
            Expanded(
              child: _books.isEmpty
                  ? const Center(child: Text('Sin resultados todavia', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: _books.length,
                      itemBuilder: (context, i) {
                        final book = _books[i];
                        final downloading = _downloading.contains(book.name);
                        return Card(
                          child: ListTile(
                            title: Text(book.title),
                            subtitle: Text('${book.sizeMb} MB · ${book.chapters.length} capitulos'),
                            trailing: downloading
                                ? const SizedBox(
                                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                : IconButton(
                                    icon: const Icon(Icons.download),
                                    onPressed: () => _download(book),
                                  ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

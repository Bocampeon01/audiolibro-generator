import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chapter.dart';
import '../services/library_service.dart';

class _JobFailed implements Exception {
  final String message;
  _JobFailed(this.message);
}

class ServerImportScreen extends StatefulWidget {
  const ServerImportScreen({super.key});

  @override
  State<ServerImportScreen> createState() => _ServerImportScreenState();
}

class _ServerImportScreenState extends State<ServerImportScreen>
    with SingleTickerProviderStateMixin {
  final _service = LibraryService();
  final _urlController = TextEditingController(text: 'http://10.0.2.2:8000');
  late final TabController _tabController;

  static const _prefKey = 'server_url';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSavedUrl();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved != null) {
      setState(() => _urlController.text = saved);
    }
  }

  Future<void> _saveUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, _urlController.text.trim().replaceAll(RegExp(r'/$'), ''));
  }

  String get _baseUrl => _urlController.text.trim().replaceAll(RegExp(r'/$'), '');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Servidor'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Descargar'),
            Tab(text: 'Generar'),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Esto solo funciona si tu celular esta conectado al mismo WiFi '
              'que la PC, y la PC tiene la web de audiolibro-generator corriendo '
              'en ese momento. Si no estas en esa red, no va a conectar.',
              style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    onChanged: (_) => _saveUrl(),
                    decoration: const InputDecoration(
                      labelText: 'URL del servidor',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _DownloadTab(service: _service, baseUrlGetter: () => _baseUrl),
                _GenerateTab(service: _service, baseUrlGetter: () => _baseUrl),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadTab extends StatefulWidget {
  final LibraryService service;
  final String Function() baseUrlGetter;

  const _DownloadTab({required this.service, required this.baseUrlGetter});

  @override
  State<_DownloadTab> createState() => _DownloadTabState();
}

class _DownloadTabState extends State<_DownloadTab> {
  List<ServerBook> _books = [];
  String? _error;
  bool _loading = false;
  final Set<String> _downloading = {};

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final books = await widget.service.fetchServerLibrary(widget.baseUrlGetter());
      if (mounted) setState(() => _books = books);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download(ServerBook item) async {
    setState(() => _downloading.add(item.name));
    try {
      await widget.service.downloadFromServer(widget.baseUrlGetter(), item);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Descargado: ${item.title}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _downloading.remove(item.name));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton(
            onPressed: _loading ? null : _search,
            child: _loading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Buscar audiolibros en el servidor'),
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
                          subtitle: Text('${book.sizeMb} MB · ${chaptersLabel(book.chaptersCount)}'),
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
    );
  }
}

class _GenerateTab extends StatefulWidget {
  final LibraryService service;
  final String Function() baseUrlGetter;

  const _GenerateTab({required this.service, required this.baseUrlGetter});

  @override
  State<_GenerateTab> createState() => _GenerateTabState();
}

class _GenerateTabState extends State<_GenerateTab> {
  VoiceCatalog? _catalog;
  String? _catalogError;
  File? _selectedFile;
  String _lang = 'auto';
  String _voice = '';

  bool _generating = false;
  String? _error;
  String? _stage;
  int _step = 0;
  int _total = 5;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    setState(() => _catalogError = null);
    try {
      final catalog = await widget.service.fetchVoices(widget.baseUrlGetter());
      if (!mounted) return;
      setState(() => _catalog = catalog);
    } catch (e) {
      if (!mounted) return;
      setState(() => _catalogError = 'No se pudo conectar al servidor: $e');
    }
  }

  Future<void> _pickFile() async {
    try {
      final file = await widget.service.pickDocument();
      if (file != null && mounted) setState(() => _selectedFile = file);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _generate() async {
    if (_selectedFile == null) return;
    setState(() {
      _generating = true;
      _error = null;
      _stage = 'Subiendo archivo...';
      _step = 0;
    });

    final baseUrl = widget.baseUrlGetter();
    try {
      final jobId =
          await widget.service.generateOnServer(baseUrl, _selectedFile!, _lang, _voice);
      final outName = await _waitForJob(baseUrl, jobId);
      if (!mounted) return;
      setState(() => _stage = 'Descargando audiolibro al celular...');
      final book = await widget.service.downloadGeneratedJob(baseUrl, jobId, outName);
      if (!mounted) return;
      setState(() {
        _generating = false;
        _selectedFile = null;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Audiolibro generado: ${book.title}')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _error = e is _JobFailed ? e.message : 'Error: $e';
      });
    }
  }

  /// Consulta el job de a una por vez (nunca dos pedidos en vuelo: con Timer.periodic
  /// dos respuestas "done" solapadas descargaban el mismo archivo en paralelo).
  /// Tolera cortes breves de red antes de rendirse. Devuelve el nombre del M4B.
  Future<String> _waitForJob(String baseUrl, String jobId) async {
    var consecutiveErrors = 0;
    while (mounted) {
      await Future.delayed(const Duration(seconds: 1));
      final Map<String, dynamic> job;
      try {
        job = await widget.service.fetchJobStatus(baseUrl, jobId);
        consecutiveErrors = 0;
      } catch (_) {
        if (++consecutiveErrors >= 10) {
          throw _JobFailed('Se perdio la conexion con el servidor');
        }
        continue;
      }
      if (!mounted) break;
      setState(() {
        _stage = job['stage'] as String?;
        _step = job['step'] as int? ?? 0;
        _total = job['total'] as int? ?? 5;
      });
      if (job['status'] == 'done') return job['out_name'] as String;
      if (job['status'] == 'error') {
        throw _JobFailed(job['error'] as String? ?? 'Fallo la generacion');
      }
    }
    throw _JobFailed('Cancelado');
  }

  @override
  Widget build(BuildContext context) {
    if (_catalogError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_catalogError!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadCatalog, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    if (_catalog == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final languages = {'auto': 'Autodetectar', ..._catalog!.languages};
    final voices = _catalog!.voices[_lang] ?? [];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: _generating ? null : _pickFile,
            icon: const Icon(Icons.upload_file),
            label: Text(_selectedFile == null
                ? 'Elegir PDF / DOCX / TXT'
                : _selectedFile!.uri.pathSegments.last),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _lang,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Idioma'),
            items: languages.entries
                .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: _generating
                ? null
                : (v) => setState(() {
                      _lang = v ?? 'auto';
                      _voice = '';
                    }),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _voice.isEmpty ? '' : _voice,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Voz'),
            items: [
              const DropdownMenuItem(value: '', child: Text('(por defecto)')),
              ...voices.map((v) => DropdownMenuItem(
                    value: v.id,
                    child: Text(v.label, overflow: TextOverflow.ellipsis),
                  )),
            ],
            onChanged: (_lang == 'auto' || _generating)
                ? null
                : (v) => setState(() => _voice = v ?? ''),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: (_selectedFile == null || _generating) ? null : _generate,
            child: const Text('Generar audiolibro'),
          ),
          if (_generating) ...[
            const SizedBox(height: 20),
            LinearProgressIndicator(value: _total > 0 ? _step / _total : null),
            const SizedBox(height: 8),
            Text(_stage ?? '...', style: const TextStyle(color: Colors.grey)),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ),
        ],
      ),
    );
  }
}

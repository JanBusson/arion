import 'package:flutter/foundation.dart';

import 'catalog_api.dart';
import 'track.dart';

final class LibraryController extends ChangeNotifier {
  LibraryController(this._api, {this.pageSize = 30});

  final CatalogApi _api;
  final int pageSize;

  final List<Track> _items = [];
  String _query = '';
  int _total = 0;
  int _generation = 0;
  bool _isInitialLoading = false;
  bool _isLoadingMore = false;
  String? _error;

  List<Track> get items => List.unmodifiable(_items);
  String get query => _query;
  int get total => _total;
  bool get isInitialLoading => _isInitialLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get error => _error;
  bool get hasMore => _items.length < _total;
  bool get isEmpty => !_isInitialLoading && _error == null && _items.isEmpty;
  CatalogApi get api => _api;

  Future<void> loadInitial() => _resetAndLoad(_query);

  Future<void> submitSearch(String value) => _resetAndLoad(value.trim());

  Future<void> clearSearch() => _resetAndLoad('');

  Future<void> retry() => _resetAndLoad(_query);

  Future<void> _resetAndLoad(String query) async {
    final generation = ++_generation;
    _query = query;
    _items.clear();
    _total = 0;
    _error = null;
    _isInitialLoading = true;
    _isLoadingMore = false;
    notifyListeners();
    try {
      final page = await _api.fetchTracks(
        limit: pageSize,
        query: query.isEmpty ? null : query,
      );
      if (generation != _generation || query != _query) {
        return;
      }
      _items.addAll(_unique(page.items));
      _total = page.total;
    } on CatalogException catch (error) {
      if (generation == _generation) {
        _error = error.message;
      }
    } on Object {
      if (generation == _generation) {
        _error = 'The library could not be loaded.';
      }
    } finally {
      if (generation == _generation) {
        _isInitialLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    if (_isInitialLoading || _isLoadingMore || !hasMore) {
      return;
    }
    final generation = _generation;
    final query = _query;
    _isLoadingMore = true;
    _error = null;
    notifyListeners();
    try {
      final page = await _api.fetchTracks(
        limit: pageSize,
        offset: _items.length,
        query: query.isEmpty ? null : query,
      );
      if (generation != _generation || query != _query) {
        return;
      }
      final knownIds = _items.map((track) => track.id).toSet();
      _items.addAll(page.items.where((track) => knownIds.add(track.id)));
      _total = page.total;
    } on CatalogException catch (error) {
      if (generation == _generation) {
        _error = error.message;
      }
    } on Object {
      if (generation == _generation) {
        _error = 'More tracks could not be loaded.';
      }
    } finally {
      if (generation == _generation) {
        _isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  Iterable<Track> _unique(Iterable<Track> values) sync* {
    final ids = <String>{};
    for (final track in values) {
      if (ids.add(track.id)) {
        yield track;
      }
    }
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }
}

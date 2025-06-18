import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:frontend/models/category_model.dart';

class CategoryService {
  static final CategoryService _instance = CategoryService._internal();
  factory CategoryService() => _instance;
  CategoryService._internal();

  List<CategoryModel>? _cachedCategories;
  bool _isLoading = false;

  final String _baseUrl = 'http://10.0.2.2:5000';

  Future<List<CategoryModel>> getCategories() async {
    if (_cachedCategories != null) {
      return _cachedCategories!;
    }

    if (_isLoading) {
      await Future.delayed(const Duration(milliseconds: 100));
      return getCategories();
    }

    _isLoading = true;
    try {
      final response = await http.get(Uri.parse('$_baseUrl/categories'));
      if (response.statusCode == 200) {
        List<dynamic> fetchedCategoriesJson = jsonDecode(response.body);
        _cachedCategories =
            fetchedCategoriesJson
                .map((json) => CategoryModel.fromJson(json))
                .toList();
        return _cachedCategories!;
      } else {
        throw Exception('Falha ao carregar categorias: ${response.statusCode}');
      }
    } catch (e) {
      _cachedCategories = null;
      rethrow;
    } finally {
      _isLoading = false;
    }
  }

  void refreshCategories() {
    _cachedCategories = null;
  }
}

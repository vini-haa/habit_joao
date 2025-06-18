import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:frontend/models/habit.dart';
import 'package:frontend/models/category_model.dart';
import 'package:frontend/services/category_service.dart';
import 'package:frontend/widgets/habit_card_with_heatmap.dart';

class HabitProgressListScreen extends StatefulWidget {
  const HabitProgressListScreen({super.key});

  @override
  State<HabitProgressListScreen> createState() =>
      _HabitProgressListScreenState();
}

class _HabitProgressListScreenState extends State<HabitProgressListScreen> {
  // --- VARIÁVEIS DE ESTADO PARA PAGINAÇÃO ---
  final List<Habit> _habits = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  final int _perPage = 10; // Menos itens por página, já que o card é maior

  // --- ESTADO PARA FILTROS ---
  List<CategoryModel> _allAvailableCategories = [];
  int? _selectedCategoryIdFilter;

  final String _baseUrl = 'http://10.0.2.2:5000';

  @override
  void initState() {
    super.initState();
    _loadCategoriesForFilter();
    _fetchHabits(page: 1, isRefresh: true);

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 400 &&
          !_isLoadingMore &&
          _hasMore) {
        _fetchHabits(page: _currentPage + 1);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCategoriesForFilter() async {
    try {
      _allAvailableCategories = await CategoryService().getCategories();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao carregar filtros: $e')));
      }
    }
  }

  Future<void> _fetchHabits({
    required int page,
    int? categoryId,
    bool isRefresh = false,
  }) async {
    if (_isLoading || _isLoadingMore) return;

    setState(() {
      if (page == 1)
        _isLoading = true;
      else
        _isLoadingMore = true;
    });

    try {
      String apiUrl = '$_baseUrl/habits?page=$page&per_page=$_perPage';
      if (categoryId != null) {
        apiUrl += '&category_id=$categoryId';
      }

      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        List<dynamic> jsonList = jsonDecode(response.body);
        List<Habit> newHabits =
            jsonList.map((json) => Habit.fromJson(json)).toList();

        setState(() {
          if (isRefresh) _habits.clear();
          _habits.addAll(newHabits);
          _currentPage = page;
          _hasMore = newHabits.length == _perPage;
        });
      } else {
        throw Exception('Falha ao carregar hábitos');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao buscar hábitos: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  void _filterHabitsBy({int? categoryId}) {
    setState(() {
      _selectedCategoryIdFilter = categoryId;
      _currentPage = 1;
      _hasMore = true;
    });
    _fetchHabits(page: 1, categoryId: categoryId, isRefresh: true);
  }

  Future<void> _refreshData() async {
    CategoryService().refreshCategories();
    _loadCategoriesForFilter();
    _filterHabitsBy(categoryId: _selectedCategoryIdFilter);
  }

  // A tela de progresso não precisa da lógica de registrar, apenas de exibir.
  // Mantemos o _refreshData para o botão de atualizar.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: <Widget>[
            SliverAppBar.large(
              title: const Text('Progresso dos Hábitos'),
              expandedHeight: 120.0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _refreshData,
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  vertical: 8.0,
                  horizontal: 12.0,
                ),
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('Todas'),
                      selected: _selectedCategoryIdFilter == null,
                      onSelected:
                          (bool selected) => _filterHabitsBy(categoryId: null),
                    ),
                    const SizedBox(width: 8),
                    ..._allAvailableCategories.map((category) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: FilterChip(
                          label: Text(category.name),
                          selected: _selectedCategoryIdFilter == category.id,
                          onSelected:
                              (bool selected) => _filterHabitsBy(
                                categoryId: selected ? category.id : null,
                              ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ),
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_habits.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Text(
                    'Nenhum hábito encontrado para exibir o progresso.',
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  if (index >= _habits.length) {
                    return _hasMore
                        ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32.0),
                          child: Center(child: CircularProgressIndicator()),
                        )
                        : const SizedBox(height: 20);
                  }
                  final habit = _habits[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: HabitCardWithHeatmap(
                      habit: habit,
                      onHabitModified: _refreshData,
                      onCheckButtonPressed: (habitToRecord) {
                        // A tela de progresso não executa ação de check,
                        // mas o parâmetro é necessário.
                      },
                      showDetails: false, // Importante para o layout desta tela
                    ),
                  );
                }, childCount: _habits.length + (_hasMore ? 1 : 0)),
              ),
          ],
        ),
      ),
    );
  }
}

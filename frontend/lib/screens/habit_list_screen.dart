import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:frontend/models/category_model.dart';
import 'package:frontend/models/habit.dart';
import 'package:frontend/screens/habit_form_screen.dart';
import 'package:frontend/services/category_service.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class HabitListScreen extends StatefulWidget {
  const HabitListScreen({super.key});

  @override
  State<HabitListScreen> createState() => _HabitListScreenState();
}

class _HabitListScreenState extends State<HabitListScreen> {
  // --- VARIÁVEIS DE ESTADO PARA PAGINAÇÃO ---
  final List<Habit> _habits = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  final int _perPage = 15;

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
              _scrollController.position.maxScrollExtent - 300 &&
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

    setState(() {
      _currentPage = 1;
      _hasMore = true;
    });
    await _fetchHabits(
      page: 1,
      categoryId: _selectedCategoryIdFilter,
      isRefresh: true,
    );
  }

  Future<void> _recordHabitCompletion(
    int habitId,
    String completionMethod, {
    int? quantityCompleted,
  }) async {
    final String apiUrl = '$_baseUrl/habit_records';
    final String recordDate = DateTime.now().toIso8601String().split('T')[0];
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(<String, dynamic>{
          'habit_id': habitId,
          'record_date': recordDate,
          'quantity_completed': quantityCompleted,
        }),
      );
      if (response.statusCode == 201) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hábito registrado com sucesso!')),
          );
        _refreshData();
      } else if (response.statusCode == 409) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hábito já registrado para hoje!')),
          );
        _refreshData();
      } else {
        final errorData = jsonDecode(response.body);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao registrar hábito: ${errorData['error']}'),
            ),
          );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro de conexão ao registrar: $e')),
        );
    }
  }

  Future<void> _showQuantityDialog(Habit habit) async {
    TextEditingController quantityController = TextEditingController();
    final formKeyDialog = GlobalKey<FormState>();
    int currentAmount = habit.currentPeriodQuantity ?? 0;
    int targetAmount = habit.targetQuantity ?? 0;
    int maxAddable = 0;
    bool canAddMore = true;

    if (habit.targetQuantity != null && habit.targetQuantity! > 0) {
      maxAddable = targetAmount - currentAmount;
      if (maxAddable <= 0) {
        canAddMore = false;
        maxAddable = 0;
      }
    } else {
      canAddMore = true;
    }

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Registrar ${habit.name}'),
          content: SingleChildScrollView(
            child: Form(
              key: formKeyDialog,
              child: ListBody(
                children: <Widget>[
                  TextFormField(
                    controller: quantityController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText:
                          habit.completionMethod == 'quantity'
                              ? 'Quantidade a adicionar'
                              : 'Minutos a adicionar',
                      helperText:
                          canAddMore && habit.targetQuantity != null
                              ? (maxAddable > 0
                                  ? 'Faltam $maxAddable para a meta.'
                                  : 'Meta já atingida.')
                              : (habit.targetQuantity == null
                                  ? 'Sem meta definida.'
                                  : null),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor, insira um valor';
                      }
                      final int? enteredQuantity = int.tryParse(value);
                      if (enteredQuantity == null || enteredQuantity <= 0) {
                        return 'Insira um número positivo válido';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Registrar'),
              onPressed: () {
                if (formKeyDialog.currentState!.validate()) {
                  int quantityEntered = int.parse(quantityController.text);
                  int quantityToRecord = quantityEntered;

                  if (habit.targetQuantity != null &&
                      habit.targetQuantity! > 0) {
                    if (currentAmount < targetAmount) {
                      int neededToComplete = targetAmount - currentAmount;
                      if (quantityEntered > neededToComplete) {
                        quantityToRecord = neededToComplete;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Valor ajustado para $quantityToRecord para atingir a meta.',
                                ),
                              ),
                            );
                          }
                        });
                      }
                    } else {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Meta já atingida. Nenhum valor adicional registrado.',
                              ),
                            ),
                          );
                        }
                      });
                      Navigator.of(context).pop();
                      return;
                    }
                  }

                  if (quantityToRecord > 0) {
                    // CORREÇÃO: A chamada da função acontece aqui dentro
                    _recordHabitCompletion(
                      habit.id,
                      habit.completionMethod,
                      quantityCompleted: quantityToRecord,
                    );
                  }
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteHabit(int habitId) async {
    final String apiUrl = '$_baseUrl/habits/$habitId';
    bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder:
          (BuildContext context) => AlertDialog(
            title: const Text('Confirmar Exclusão'),
            content: const Text(
              'Tem certeza de que deseja excluir este hábito? Todos os registros relacionados serão apagados.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Excluir'),
              ),
            ],
          ),
    );
    if (confirmDelete == true && mounted) {
      try {
        final response = await http.delete(Uri.parse(apiUrl));
        if (response.statusCode == 200) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Hábito excluído com sucesso!')),
            );
          _refreshData();
        } else {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Erro ao excluir hábito: ${response.body}'),
              ),
            );
        }
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro de conexão ao excluir: $e')),
          );
      }
    }
  }

  Future<void> _undoTodayRecord(int habitId) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder:
          (BuildContext context) => AlertDialog(
            title: const Text('Limpar Registro de Hoje?'),
            content: const Text(
              'Tem certeza que deseja limpar o progresso registrado hoje para este hábito?',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Limpar'),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    final String apiUrl = '$_baseUrl/habit_records/today?habit_id=$habitId';
    try {
      final response = await http.delete(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                jsonDecode(response.body)['message'] ??
                    'Registro de hoje limpo com sucesso!',
              ),
            ),
          );
        _refreshData();
      } else {
        final errorData = jsonDecode(response.body);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Erro ao limpar registro: ${errorData['error'] ?? response.body}',
              ),
            ),
          );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro de conexão ao limpar registro: $e')),
        );
    }
  }

  Future<void> _exportData() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/export_data'));
      if (response.statusCode == 200) {
        final String jsonData = response.body;
        final directory = await getDownloadsDirectory();
        if (directory == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Não foi possível acessar o diretório de downloads.',
                ),
              ),
            );
          }
          return;
        }
        final String timestamp =
            DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
        final String fileName = 'habits_backup_$timestamp.json';
        final File file = File('${directory.path}/$fileName');
        await file.writeAsString(jsonData);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Dados exportados para: ${file.path}')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Erro ao exportar dados: ${response.statusCode} - ${response.body}',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro de conexão ao exportar: $e')),
        );
      }
    }
  }

  Future<void> _importData() async {
    bool confirmImport =
        await showDialog<bool>(
          context: context,
          builder:
              (BuildContext context) => AlertDialog(
                title: const Text('Importar Dados?'),
                content: const Text(
                  'Isso substituirá TODOS os dados existentes. Deseja continuar?',
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Importar e Substituir'),
                  ),
                ],
              ),
        ) ??
        false;

    if (!confirmImport || !mounted) return;

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        String jsonData = await file.readAsString();
        final response = await http.post(
          Uri.parse('$_baseUrl/import_data'),
          headers: <String, String>{
            'Content-Type': 'application/json; charset=UTF-8',
          },
          body: jsonData,
        );
        if (mounted) {
          if (response.statusCode == 201) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Dados importados com sucesso!')),
            );
            _refreshData();
          } else {
            final errorData = jsonDecode(response.body);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Erro ao importar dados: ${errorData['error'] ?? response.body}',
                ),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Importação cancelada.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro durante a importação: $e')),
        );
      }
    }
  }

  Future<void> _deleteAllData() async {
    bool confirmDelete =
        await showDialog<bool>(
          context: context,
          builder:
              (BuildContext context) => AlertDialog(
                title: const Text('EXCLUIR TODOS OS DADOS?'),
                content: const Text(
                  'ATENÇÃO: Esta ação é irreversível e apagará todos os seus hábitos, categorias e históricos. Deseja continuar?',
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('SIM, EXCLUIR TUDO'),
                  ),
                ],
              ),
        ) ??
        false;

    if (!confirmDelete || !mounted) return;

    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/delete_all_data'),
      );
      if (mounted) {
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Todos os dados foram excluídos com sucesso!'),
            ),
          );
          _refreshData();
        } else {
          final errorData = jsonDecode(response.body);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Erro ao excluir dados: ${errorData['error'] ?? response.body}',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro de conexão ao excluir dados: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: <Widget>[
            SliverAppBar.large(
              title: const Text('Meus Hábitos'),
              expandedHeight: 120.0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _refreshData,
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'export')
                      _exportData();
                    else if (value == 'import')
                      _importData();
                    else if (value == 'delete_all')
                      _deleteAllData();
                  },
                  itemBuilder:
                      (BuildContext context) => <PopupMenuEntry<String>>[
                        const PopupMenuItem<String>(
                          value: 'import',
                          child: ListTile(
                            leading: Icon(Icons.file_upload_outlined),
                            title: Text('Importar Dados'),
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'export',
                          child: ListTile(
                            leading: Icon(Icons.file_download_outlined),
                            title: Text('Exportar Dados'),
                          ),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem<String>(
                          value: 'delete_all',
                          child: ListTile(
                            leading: Icon(
                              Icons.delete_forever_outlined,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            title: Text(
                              'Deletar Todos os Dados',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                      ],
                  icon: const Icon(Icons.manage_history_outlined),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  vertical: 8.0,
                  horizontal: 12.0,
                ),
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
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text(
                      'Nenhum hábito encontrado.\nToque no botão "+" para adicionar o primeiro!',
                      textAlign: TextAlign.center,
                    ),
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
                  bool isQuantitative =
                      habit.completionMethod == 'quantity' ||
                      habit.completionMethod == 'minutes';
                  bool isBoolean = habit.completionMethod == 'boolean';
                  bool isTargetMet = false;
                  double progressFraction = 0.0;
                  bool hasTargetAndIsQuantitative = false;
                  IconData mainButtonIcon;
                  Color mainButtonContainerColor;
                  Color mainButtonIconColor;
                  bool disableMainButtonTap;

                  if (isQuantitative) {
                    if (habit.targetQuantity != null &&
                        habit.targetQuantity! > 0) {
                      hasTargetAndIsQuantitative = true;
                      isTargetMet =
                          (habit.currentPeriodQuantity ?? 0) >=
                          habit.targetQuantity!;
                      progressFraction =
                          (habit.currentPeriodQuantity ?? 0).toDouble() /
                          habit.targetQuantity!.toDouble();
                      progressFraction = progressFraction.clamp(0.0, 1.0);
                    } else {
                      hasTargetAndIsQuantitative = false;
                      isTargetMet = (habit.currentPeriodQuantity ?? 0) > 0;
                      progressFraction = isTargetMet ? 1.0 : 0.0;
                    }

                    if (isTargetMet && hasTargetAndIsQuantitative) {
                      mainButtonIcon = Icons.check_rounded;
                      mainButtonContainerColor =
                          Theme.of(context).colorScheme.surfaceContainerLowest;
                      mainButtonIconColor =
                          Theme.of(context).colorScheme.primary;
                      disableMainButtonTap = true;
                    } else {
                      mainButtonIcon = Icons.add_rounded;
                      mainButtonContainerColor =
                          Theme.of(context).colorScheme.primaryContainer;
                      mainButtonIconColor =
                          Theme.of(context).colorScheme.onPrimaryContainer;
                      disableMainButtonTap = false;
                    }
                  } else {
                    // Boolean
                    isTargetMet = habit.isCompletedToday;
                    mainButtonIcon = Icons.check_rounded;
                    if (habit.isCompletedToday) {
                      mainButtonContainerColor =
                          Theme.of(context).colorScheme.surfaceContainerHighest;
                      mainButtonIconColor =
                          Theme.of(context).colorScheme.onSurfaceVariant;
                      progressFraction = 1.0;
                      disableMainButtonTap = true;
                    } else {
                      mainButtonContainerColor =
                          Theme.of(context).colorScheme.primaryContainer;
                      mainButtonIconColor =
                          Theme.of(context).colorScheme.onPrimaryContainer;
                      progressFraction = 0.0;
                      disableMainButtonTap = false;
                    }
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 0,
                    ),
                    child: Card(
                      margin: const EdgeInsets.symmetric(vertical: 6.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 2,
                      clipBehavior: Clip.antiAlias,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final cardWidth = constraints.maxWidth;
                          final progressBarWidth = cardWidth * progressFraction;
                          final Color progressColor = Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.25);

                          return Stack(
                            children: [
                              if (hasTargetAndIsQuantitative || isBoolean)
                                Positioned.fill(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      width: progressBarWidth,
                                      decoration: BoxDecoration(
                                        color: progressColor,
                                      ),
                                    ),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 16.0,
                                  left: 16.0,
                                  right: 16.0,
                                  bottom: 8.0,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        right: 60.0,
                                      ),
                                      child: Text(
                                        habit.name,
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    if (habit.categories.isNotEmpty)
                                      Wrap(
                                        spacing: 4.0,
                                        runSpacing: 0.0,
                                        children:
                                            habit.categories
                                                .map(
                                                  (cat) => Chip(
                                                    label: Text(cat.name),
                                                    padding: EdgeInsets.zero,
                                                    labelPadding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 6.0,
                                                        ),
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    labelStyle: TextStyle(
                                                      fontSize: 10,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant
                                                          .withOpacity(0.8),
                                                    ),
                                                    materialTapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                    backgroundColor:
                                                        Theme.of(context)
                                                            .colorScheme
                                                            .background,
                                                    side: BorderSide(
                                                      color:
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .outlineVariant,
                                                    ),
                                                  ),
                                                )
                                                .toList(),
                                      ),
                                    const SizedBox(height: 8),
                                    if (isQuantitative)
                                      Text(
                                        'Progresso: ${habit.currentPeriodQuantity ?? 0}${hasTargetAndIsQuantitative ? " de ${habit.targetQuantity}" : ""} ${habit.completionMethod == 'minutes' ? 'min' : 'x'}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant
                                              .withOpacity(0.8),
                                        ),
                                      )
                                    else if (isBoolean &&
                                        habit.isCompletedToday)
                                      Text(
                                        'Completo hoje!',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      )
                                    else if (isBoolean &&
                                        !habit.isCompletedToday)
                                      Text(
                                        'Pendente',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant
                                              .withOpacity(0.8),
                                        ),
                                      ),
                                    const SizedBox(height: 4),
                                    if (habit.currentStreak > 0)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.local_fire_department_rounded,
                                            color: Colors.orangeAccent,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${habit.currentStreak} ${habit.currentStreak == 1 ? "dia" : "dias"}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant
                                                  .withOpacity(0.8),
                                            ),
                                          ),
                                        ],
                                      )
                                    else
                                      const SizedBox(height: 18),
                                    const SizedBox(height: 10),
                                  ],
                                ),
                              ),
                              Positioned(
                                top: 12,
                                right: 12,
                                child: Material(
                                  color: mainButtonContainerColor,
                                  borderRadius: BorderRadius.circular(12.0),
                                  elevation: disableMainButtonTap ? 0 : 2,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12.0),
                                    onTap:
                                        disableMainButtonTap
                                            ? null
                                            : () {
                                              if (isQuantitative) {
                                                _showQuantityDialog(habit);
                                              } else {
                                                _recordHabitCompletion(
                                                  habit.id,
                                                  habit.completionMethod,
                                                );
                                              }
                                            },
                                    child: Container(
                                      width: 55,
                                      height: 55,
                                      alignment: Alignment.center,
                                      child: Icon(
                                        mainButtonIcon,
                                        size: 26.0,
                                        color: mainButtonIconColor,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 8,
                                right: 8,
                                child: PopupMenuButton<String>(
                                  icon: Icon(
                                    Icons.more_vert,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withOpacity(0.7),
                                    size: 26,
                                  ),
                                  offset: const Offset(0, 30),
                                  onSelected: (value) async {
                                    if (value == 'edit') {
                                      final result = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (context) =>
                                                  HabitFormScreen(habit: habit),
                                        ),
                                      );
                                      if (result == true) {
                                        _refreshData();
                                      }
                                    } else if (value == 'delete') {
                                      _deleteHabit(habit.id);
                                    } else if (value == 'undo_today') {
                                      _undoTodayRecord(habit.id);
                                    }
                                  },
                                  itemBuilder:
                                      (BuildContext context) =>
                                          <PopupMenuEntry<String>>[
                                            const PopupMenuItem<String>(
                                              value: 'edit',
                                              child: Text('Editar'),
                                            ),
                                            const PopupMenuItem<String>(
                                              value: 'undo_today',
                                              child: Text(
                                                'Limpar registro de hoje',
                                              ),
                                            ),
                                            const PopupMenuItem<String>(
                                              value: 'delete',
                                              child: Text('Excluir'),
                                            ),
                                          ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
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

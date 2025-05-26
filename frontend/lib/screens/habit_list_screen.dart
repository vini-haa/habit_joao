// frontend/lib/screens/habit_list_screen.dart
import 'dart:convert';
import 'dart:io'; // Para File
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:frontend/models/category_model.dart';
import 'package:frontend/models/habit.dart';
import 'package:frontend/screens/habit_form_screen.dart';
import 'package:frontend/services/notification_service.dart';
import 'package:http/http.dart' as http;

class HabitListScreen extends StatefulWidget {
  const HabitListScreen({super.key});

  @override
  _HabitListScreenState createState() => _HabitListScreenState();
}

class _HabitListScreenState extends State<HabitListScreen> {
  Future<List<Habit>>? _futureDisplayedHabits;
  List<CategoryModel> _categoriesInUseForFilter = [];
  int? _selectedCategoryIdFilter;

  final String _baseUrl = 'http://10.0.2.2:5000';

  @override
  void initState() {
    super.initState();
    _loadAllHabitsAndSetupFilters();
  }

  void refreshHabits() {
    _loadAllHabitsAndSetupFilters();
  }

  Future<void> _loadAllHabitsAndSetupFilters() async {
    if (!mounted) return;
    setState(() {
      _selectedCategoryIdFilter = null;
      _futureDisplayedHabits = fetchHabits(categoryId: null);
    });
    try {
      final List<Habit>? allHabits = await _futureDisplayedHabits;
      if (allHabits != null && mounted) {
        Set<CategoryModel> usedCategoriesSet = {};
        for (var habit in allHabits) {
          for (var category in habit.categories) {
            usedCategoriesSet.add(category);
          }
        }
        List<CategoryModel> sortedUsedCategories = usedCategoriesSet.toList();
        sortedUsedCategories.sort((a, b) => a.name.compareTo(b.name));
        setState(() {
          _categoriesInUseForFilter = sortedUsedCategories;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar e configurar filtros: $e')),
        );
        setState(() {
          _categoriesInUseForFilter = [];
          _futureDisplayedHabits = Future.value([]);
        });
      }
    }
  }

  void _filterHabitsBy({int? categoryId}) {
    if (!mounted) return;
    setState(() {
      _selectedCategoryIdFilter = categoryId;
      _futureDisplayedHabits = fetchHabits(categoryId: categoryId);
    });
  }

  Future<List<Habit>> fetchHabits({int? categoryId}) async {
    String apiUrl = '$_baseUrl/habits';
    if (categoryId != null) {
      apiUrl += '?category_id=$categoryId';
    }
    try {
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList.map((json) => Habit.fromJson(json)).toList();
      } else {
        throw Exception('Falha ao carregar hábitos: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Falha ao conectar com o backend: $e');
    }
  }

  Future<void> _refreshDataAfterModification() async {
    await _loadAllHabitsAndSetupFilters();
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
      if (!mounted) return;
      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hábito registrado com sucesso!')),
        );
        _refreshDataAfterModification();
      } else if (response.statusCode == 409) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hábito já registrado para hoje!')),
        );
        _refreshDataAfterModification();
      } else {
        final errorData = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao registrar hábito: ${errorData['error']}'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
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
              'Tem certeza de que deseja excluir este hábito? Todos os registros e lembretes relacionados serão apagados.',
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
        if (!mounted) return;
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hábito excluído com sucesso!')),
          );
          await NotificationService().cancelNotification(habitId);
          await NotificationService().cancelWeeklyNotificationsForHabit(
            habitId,
          );
          _refreshDataAfterModification();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao excluir hábito: ${response.body}')),
          );
        }
      } catch (e) {
        if (!mounted) return;
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

    if (confirm != true || !mounted) return;

    final String apiUrl = '$_baseUrl/habit_records/today?habit_id=$habitId';
    try {
      final response = await http.delete(Uri.parse(apiUrl));
      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              jsonDecode(response.body)['message'] ??
                  'Registro de hoje limpo com sucesso!',
            ),
          ),
        );
        _refreshDataAfterModification();
      } else {
        final errorData = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao limpar registro: ${errorData['error'] ?? response.body}',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro de conexão ao limpar registro: $e')),
      );
    }
  }

  Future<void> _exportData() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/export_data'));
      if (!mounted) return;
      if (response.statusCode == 200) {
        final String jsonData = response.body;
        final String timestamp =
            DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
        final String fileName = 'habits_backup_$timestamp.json';
        final Uint8List bytes = Uint8List.fromList(utf8.encode(jsonData));

        String? selectedDirectory = await FilePicker.platform.saveFile(
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: bytes,
        );

        if (selectedDirectory != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Dados exportados para: $selectedDirectory'),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Exportação cancelada.')),
            );
          }
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

        if (jsonData.trim().isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Erro: O arquivo selecionado está vazio ou não contém dados JSON válidos.',
                ),
              ),
            );
          }
          return;
        }

        final response = await http.post(
          Uri.parse('$_baseUrl/import_data'),
          headers: <String, String>{
            'Content-Type': 'application/json; charset=UTF-8',
          },
          body: utf8.encode(jsonData), // Envia como bytes UTF-8
        );

        if (!mounted) return;
        if (response.statusCode == 201) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Dados importados com sucesso!')),
          );
          _refreshDataAfterModification();
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
      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Todos os dados foram excluídos com sucesso!'),
          ),
        );
        _refreshDataAfterModification();
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
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar.large(
            title: const Text('Meus Hábitos'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadAllHabitsAndSetupFilters,
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
            child:
                _futureDisplayedHabits != null
                    ? Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8.0,
                        horizontal: 4.0,
                      ),
                      // CORREÇÃO AQUI: O child do Padding é o SingleChildScrollView
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4.0,
                              ),
                              child: FilterChip(
                                label: Text(
                                  'Todas',
                                  style: TextStyle(
                                    color:
                                        _selectedCategoryIdFilter == null
                                            ? Theme.of(
                                              context,
                                            ).colorScheme.onPrimaryContainer
                                            : Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                selected: _selectedCategoryIdFilter == null,
                                onSelected:
                                    (bool selected) =>
                                        _filterHabitsBy(categoryId: null),
                                checkmarkColor:
                                    _selectedCategoryIdFilter == null
                                        ? Theme.of(
                                          context,
                                        ).colorScheme.onPrimaryContainer
                                        : null,
                                selectedColor:
                                    _selectedCategoryIdFilter == null
                                        ? Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer
                                        : null,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8.0),
                                  side: BorderSide(
                                    color:
                                        _selectedCategoryIdFilter == null
                                            ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                            : Theme.of(
                                              context,
                                            ).colorScheme.outlineVariant,
                                  ),
                                ),
                                backgroundColor:
                                    Theme.of(context).colorScheme.surface,
                              ),
                            ),
                            ..._categoriesInUseForFilter.map((category) {
                              bool isSelected =
                                  _selectedCategoryIdFilter == category.id;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4.0,
                                ),
                                child: FilterChip(
                                  label: Text(
                                    category.name,
                                    style: TextStyle(
                                      color:
                                          isSelected
                                              ? Theme.of(
                                                context,
                                              ).colorScheme.onPrimaryContainer
                                              : Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  selected: isSelected,
                                  onSelected:
                                      (bool selected) => _filterHabitsBy(
                                        categoryId:
                                            selected ? category.id : null,
                                      ),
                                  checkmarkColor:
                                      isSelected
                                          ? Theme.of(
                                            context,
                                          ).colorScheme.onPrimaryContainer
                                          : null,
                                  selectedColor:
                                      isSelected
                                          ? Theme.of(
                                            context,
                                          ).colorScheme.primaryContainer
                                          : null,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8.0),
                                    side: BorderSide(
                                      color:
                                          isSelected
                                              ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                              : Theme.of(
                                                context,
                                              ).colorScheme.outlineVariant,
                                    ),
                                  ),
                                  backgroundColor:
                                      Theme.of(context).colorScheme.surface,
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    )
                    : const SizedBox.shrink(),
          ),
          FutureBuilder<List<Habit>>(
            future: _futureDisplayedHabits,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              } else if (snapshot.hasError) {
                return SliverFillRemaining(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'Erro ao carregar hábitos: ${snapshot.error}\nPor favor, tente atualizar.',
                      ),
                    ),
                  ),
                );
              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: Text('Nenhum hábito encontrado.')),
                );
              } else {
                final habits = snapshot.data!;
                return SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    Habit habit = habits[index];
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
                            Theme.of(
                              context,
                            ).colorScheme.surfaceContainerLowest;
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
                      // Booleano
                      isTargetMet = habit.isCompletedToday;
                      mainButtonIcon = Icons.check_rounded;
                      if (habit.isCompletedToday) {
                        mainButtonContainerColor =
                            Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest;
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
                            final progressBarWidth =
                                cardWidth * progressFraction;
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                        )
                                      else if (habit.countMethod == 'weekly' ||
                                          habit.countMethod == 'monthly')
                                        Text(
                                          'Progresso: ${habit.currentPeriodDaysCompleted ?? 0} de ${habit.targetDaysPerWeek ?? 'N/A'} dias',
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
                                            Icon(
                                              Icons
                                                  .local_fire_department_rounded,
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
                                                (context) => HabitFormScreen(
                                                  habit: habit,
                                                ),
                                          ),
                                        );
                                        if (result == true && mounted) {
                                          _refreshDataAfterModification();
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
                  }, childCount: habits.length),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:frontend/models/habit.dart';
import 'package:frontend/models/category_model.dart';
import 'package:frontend/screens/selection_screen.dart';
import 'package:frontend/services/notification_service.dart'; // Verifique o caminho
import 'package:intl/intl.dart';

class HabitFormScreen extends StatefulWidget {
  final Habit? habit;

  const HabitFormScreen({super.key, this.habit});

  @override
  _HabitFormScreenState createState() => _HabitFormScreenState();
}

class _HabitFormScreenState extends State<HabitFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _targetQuantityController =
      TextEditingController();
  final TextEditingController _targetDaysPerWeekController =
      TextEditingController();

  String? _selectedCountMethod;
  String? _selectedCompletionMethod;
  List<CategoryModel> _availableCategories = [];
  List<CategoryModel> _selectedCategories = [];

  bool _formChanged = false;
  bool _isLoadingCategories = true;

  // Campos de Lembrete
  bool _reminderEnabled = false;
  TimeOfDay? _selectedReminderTime;
  final Map<String, bool> _selectedReminderDays = {
    'MON': false,
    'TUE': false,
    'WED': false,
    'THU': false,
    'FRI': false,
    'SAT': false,
    'SUN': false,
  };
  final List<String> _dayKeys = [
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
    'SAT',
    'SUN',
  ];
  final List<String> _dayDisplayNames = [
    'Seg',
    'Ter',
    'Qua',
    'Qui',
    'Sex',
    'Sáb',
    'Dom',
  ];

  final String _baseUrl = 'http://10.0.2.2:5000';

  final Map<String, String> _intervalDisplayNames = {
    'daily': 'Diário',
    'weekly': 'Semanal',
    'monthly': 'Mensal',
  };
  final Map<String, String> _completionTypeDisplayNames = {
    'boolean': 'Sim/Não',
    'quantity': 'Quantidade',
    'minutes': 'Minutos',
  };

  @override
  void initState() {
    super.initState();
    _fetchAvailableCategories();

    if (widget.habit != null) {
      _nameController.text = widget.habit!.name;
      _descriptionController.text = widget.habit!.description ?? '';
      _selectedCountMethod = widget.habit!.countMethod;
      _selectedCompletionMethod = widget.habit!.completionMethod;
      _targetQuantityController.text =
          (widget.habit!.targetQuantity ?? '').toString();
      _targetDaysPerWeekController.text =
          (widget.habit!.targetDaysPerWeek ?? '').toString();

      // Inicializar campos de lembrete
      _reminderEnabled = widget.habit!.reminderEnabled;
      if (widget.habit!.reminderTime != null) {
        try {
          List<String> parts = widget.habit!.reminderTime!.split(':');
          _selectedReminderTime = TimeOfDay(
            hour: int.parse(parts[0]),
            minute: int.parse(parts[1]),
          );
        } catch (e) {
          _selectedReminderTime = null;
        }
      }
      if (widget.habit!.reminderDays != null) {
        for (String dayKey in _dayKeys) {
          _selectedReminderDays[dayKey] = widget.habit!.reminderDays!.contains(
            dayKey,
          );
        }
      }
    }
  }

  Future<void> _fetchAvailableCategories() async {
    // ... (código existente)
    setState(() => _isLoadingCategories = true);
    try {
      final response = await http.get(Uri.parse('$_baseUrl/categories'));
      if (response.statusCode == 200) {
        List<dynamic> fetchedCategoriesJson = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _availableCategories =
                fetchedCategoriesJson
                    .map((json) => CategoryModel.fromJson(json))
                    .toList();
            if (widget.habit != null && widget.habit!.categories.isNotEmpty) {
              _selectedCategories =
                  widget.habit!.categories
                      .map(
                        (habitCat) => _availableCategories.firstWhere(
                          (availCat) => availCat.id == habitCat.id,
                          orElse:
                              () =>
                                  habitCat, // Mantém o original se não encontrar (improvável)
                        ),
                      )
                      .toList();
            }
            _isLoadingCategories = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingCategories = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Falha ao carregar categorias: ${response.statusCode}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingCategories = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar categorias: $e')),
      );
    }
  }

  Future<void> _submitHabit() async {
    if (_selectedCategories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, selecione ao menos uma categoria.'),
        ),
      );
      if (!_formChanged) setState(() => _formChanged = true);
      return;
    }

    if (_reminderEnabled && _selectedReminderTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, selecione um horário para o lembrete.'),
        ),
      );
      if (!_formChanged) setState(() => _formChanged = true);
      return;
    }

    if (_reminderEnabled &&
        _selectedReminderDays.values.where((selected) => selected).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Por favor, selecione ao menos um dia para o lembrete.',
          ),
        ),
      );
      if (!_formChanged) setState(() => _formChanged = true);
      return;
    }

    if (!_formKey.currentState!.validate()) {
      if (!_formChanged) setState(() => _formChanged = true);
      return;
    }

    final bool isEditing = widget.habit != null;
    String apiUrl = '$_baseUrl/habits';
    String successMessage = 'Hábito adicionado com sucesso!';
    String errorMessage = 'Erro ao adicionar hábito:';

    if (isEditing) {
      apiUrl = '$_baseUrl/habits/${widget.habit!.id}';
      successMessage = 'Hábito atualizado com sucesso!';
      errorMessage = 'Erro ao atualizar hábito:';
    }

    List<int> selectedCategoryIds =
        _selectedCategories.map((cat) => cat.id).toList();
    List<String> activeReminderDays = [];
    if (_reminderEnabled) {
      _selectedReminderDays.forEach((key, value) {
        if (value) activeReminderDays.add(key);
      });
    }

    try {
      final Map<String, dynamic> bodyData = {
        'name': _nameController.text,
        'description':
            _descriptionController.text.isEmpty
                ? null
                : _descriptionController.text,
        'count_method': _selectedCountMethod,
        'completion_method': _selectedCompletionMethod,
        'target_quantity':
            (_selectedCompletionMethod == 'quantity' ||
                    _selectedCompletionMethod == 'minutes')
                ? (_targetQuantityController.text.isEmpty
                    ? null
                    : int.parse(_targetQuantityController.text))
                : null,
        'target_days_per_week':
            _targetDaysPerWeekController.text.isEmpty
                ? null
                : int.parse(_targetDaysPerWeekController.text),
        'category_ids': selectedCategoryIds,
        'reminder_enabled': _reminderEnabled,
        'reminder_time':
            _reminderEnabled && _selectedReminderTime != null
                ? "${_selectedReminderTime!.hour.toString().padLeft(2, '0')}:${_selectedReminderTime!.minute.toString().padLeft(2, '0')}"
                : null,
        'reminder_days':
            _reminderEnabled && activeReminderDays.isNotEmpty
                ? activeReminderDays
                : null,
      };

      final response =
          isEditing
              ? await http.put(
                Uri.parse(apiUrl),
                headers: <String, String>{
                  'Content-Type': 'application/json; charset=UTF-8',
                },
                body: jsonEncode(bodyData),
              )
              : await http.post(
                Uri.parse(apiUrl),
                headers: <String, String>{
                  'Content-Type': 'application/json; charset=UTF-8',
                },
                body: jsonEncode(bodyData),
              );

      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
        _formChanged = false;

        int habitId =
            isEditing ? widget.habit!.id : jsonDecode(response.body)['id'];
        String habitName = _nameController.text;

        // Cancelar notificações antigas (se estiver editando)
        if (isEditing) {
          await NotificationService().cancelNotification(
            widget.habit!.id,
          ); // Para lembretes diários antigos
          await NotificationService().cancelWeeklyNotificationsForHabit(
            widget.habit!.id,
          ); // Para lembretes semanais antigos
        }

        if (_reminderEnabled &&
            _selectedReminderTime != null &&
            activeReminderDays.isNotEmpty) {
          List<int> daysToSchedule = [];
          for (String dayKey in activeReminderDays) {
            daysToSchedule.add(
              _dayKeys.indexOf(dayKey) + 1,
            ); // Converte MON -> 1 (DateTime.monday), etc.
          }

          // Se for diário (todos os dias da semana selecionados) OU se count_method for 'daily'
          // e apenas um dia qualquer estiver selecionado (mas o usuário quer diariamente)
          // Por simplicidade, se 'daily' for o intervalo do hábito, o lembrete será diário
          // ignorando os dias selecionados (ou melhor, assume-se que serão todos)
          if (_selectedCountMethod == 'daily' ||
              activeReminderDays.length == 7) {
            await NotificationService().scheduleDailyNotification(
              id: habitId,
              title: 'Lembrete de Hábito',
              body: 'Não se esqueça de completar: $habitName',
              time: _selectedReminderTime!,
            );
          } else {
            // Agendamento Semanal para dias específicos
            await NotificationService().scheduleWeeklyNotification(
              id: habitId,
              title: 'Lembrete de Hábito',
              body: 'Não se esqueça de completar: $habitName',
              time: _selectedReminderTime!,
              days: daysToSchedule,
            );
          }
        } else {
          // Se lembretes foram desabilitados ou incompletos
          await NotificationService().cancelNotification(habitId);
          await NotificationService().cancelWeeklyNotificationsForHabit(
            habitId,
          );
        }

        Navigator.pop(
          context,
          true,
        ); // true indica que algo mudou e a lista deve ser atualizada
      } else {
        final errorData = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$errorMessage ${errorData['error']}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro de conexão: $e')));
    }
  }

  void _showCategorySelectionDialog() {
    // ... (código existente)
    if (_isLoadingCategories) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Carregando categorias...')));
      return;
    }
    if (_availableCategories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma categoria disponível para seleção.'),
        ),
      );
      return;
    }

    List<CategoryModel> tempSelectedCategories = List.from(_selectedCategories);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Permite que o BottomSheet seja maior
      builder: (BuildContext context) {
        return StatefulBuilder(
          // Para atualizar o estado dentro do BottomSheet
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16.0,
                30.0,
                16.0,
                MediaQuery.of(context).viewInsets.bottom + 16.0,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                ), // Limita altura
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Selecione as Categorias',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      // Para permitir scroll se muitas categorias
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 8.0,
                          runSpacing: 4.0,
                          children:
                              _availableCategories.map((category) {
                                final bool isSelected = tempSelectedCategories
                                    .any((sc) => sc.id == category.id);
                                return FilterChip(
                                  label: Text(category.name),
                                  selected: isSelected,
                                  onSelected: (bool? selected) {
                                    setModalState(() {
                                      // Usa o setModalState do StatefulBuilder
                                      if (selected == true) {
                                        if (!isSelected)
                                          tempSelectedCategories.add(category);
                                      } else {
                                        tempSelectedCategories.removeWhere(
                                          (sc) => sc.id == category.id,
                                        );
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          child: const Text('Cancelar'),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          child: const Text('OK'),
                          onPressed: () {
                            setState(() {
                              // Usa o setState da tela principal
                              _selectedCategories = List.from(
                                tempSelectedCategories,
                              );
                              _formChanged = true;
                            });
                            Navigator.of(context).pop();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _selectReminderTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedReminderTime ?? TimeOfDay.now(),
    );
    if (picked != null && picked != _selectedReminderTime) {
      setState(() {
        _selectedReminderTime = picked;
        _formChanged = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String appBarTitle =
        widget.habit == null ? 'Cadastrar Hábito' : 'Editar Hábito';
    final String buttonText =
        widget.habit == null ? 'Adicionar Hábito' : 'Salvar Alterações';
    final bool isEditing = widget.habit != null;

    return WillPopScope(
      onWillPop: () async {
        if (_formChanged) {
          return await showDialog<bool>(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text('Descartar alterações?'),
                    content: const Text(
                      'Você tem alterações não salvas. Deseja sair e perdê-las?',
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Não'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Sim'),
                      ),
                    ],
                  );
                },
              ) ??
              false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(appBarTitle),
          leading:
              isEditing
                  ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () async {
                      if (_formChanged) {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              title: const Text('Descartar alterações?'),
                              content: const Text(
                                'Você tem alterações não salvas. Deseja sair e perdê-las?',
                              ),
                              actions: <Widget>[
                                TextButton(
                                  onPressed:
                                      () => Navigator.of(context).pop(false),
                                  child: const Text('Não'),
                                ),
                                TextButton(
                                  onPressed:
                                      () => Navigator.of(context).pop(true),
                                  child: const Text('Sim'),
                                ),
                              ],
                            );
                          },
                        );
                        if (confirm == true) {
                          Navigator.pop(context);
                        }
                      } else {
                        Navigator.pop(context);
                      }
                    },
                  )
                  : null,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            onChanged: () {
              if (!_formChanged) setState(() => _formChanged = true);
            },
            child: ListView(
              children: <Widget>[
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome do Hábito',
                    border: OutlineInputBorder(),
                  ),
                  validator:
                      (value) =>
                          (value == null || value.isEmpty)
                              ? 'Por favor, insira o nome do hábito'
                              : null,
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text("Categorias"),
                  subtitle:
                      _isLoadingCategories
                          ? const Text("Carregando categorias...")
                          : Text(
                            _selectedCategories.isEmpty
                                ? "Nenhuma selecionada (toque para escolher)"
                                : _selectedCategories
                                    .map((c) => c.name)
                                    .join(', '),
                          ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 18),
                  onTap: _showCategorySelectionDialog,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4.0),
                    side: BorderSide(
                      color:
                          Theme.of(
                            context,
                          ).inputDecorationTheme.border?.borderSide.color ??
                          Colors.grey,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 8.0,
                    horizontal: 12.0,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Descrição (opcional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  readOnly: true,
                  controller: TextEditingController(
                    text:
                        _selectedCountMethod != null
                            ? _intervalDisplayNames[_selectedCountMethod]
                            : '',
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Intervalo',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.arrow_forward_ios, size: 18),
                  ),
                  onTap: () async {
                    final selectedValue = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => SelectionScreen(
                              title: 'Selecionar Intervalo',
                              options: _intervalDisplayNames,
                              initialValue: _selectedCountMethod,
                            ),
                      ),
                    );
                    if (selectedValue != null) {
                      setState(() {
                        _selectedCountMethod = selectedValue;
                        _formChanged = true;
                      });
                    }
                  },
                  validator:
                      (value) =>
                          (value == null || value.isEmpty)
                              ? 'Por favor, selecione o intervalo.'
                              : null,
                ),
                const SizedBox(height: 16),
                if (_selectedCountMethod == 'weekly' ||
                    _selectedCountMethod == 'monthly')
                  QuantityInput(
                    controller: _targetDaysPerWeekController,
                    labelText: 'Dias Alvo por Período (ex: 4)',
                    onChanged: (value) {
                      if (!_formChanged) setState(() => _formChanged = true);
                    },
                    validator: (value) {
                      if ((_selectedCountMethod == 'weekly' ||
                              _selectedCountMethod == 'monthly') &&
                          (value == null || value.isEmpty)) {
                        return 'Este campo é obrigatório para hábitos semanais/mensais';
                      }
                      if (value != null &&
                          value.isNotEmpty &&
                          int.tryParse(value) == null)
                        return 'Por favor, insira um número válido';
                      return null;
                    },
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  readOnly: true,
                  controller: TextEditingController(
                    text:
                        _selectedCompletionMethod != null
                            ? _completionTypeDisplayNames[_selectedCompletionMethod]
                            : '',
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Tipo de Conclusão',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.arrow_forward_ios, size: 18),
                  ),
                  onTap: () async {
                    final selectedValue = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => SelectionScreen(
                              title: 'Selecionar Tipo de Conclusão',
                              options: _completionTypeDisplayNames,
                              initialValue: _selectedCompletionMethod,
                            ),
                      ),
                    );
                    if (selectedValue != null) {
                      setState(() {
                        _selectedCompletionMethod = selectedValue;
                        _formChanged = true;
                      });
                    }
                  },
                  validator:
                      (value) =>
                          (value == null || value.isEmpty)
                              ? 'Por favor, selecione o tipo de completude.'
                              : null,
                ),
                const SizedBox(height: 16),
                if (_selectedCompletionMethod == 'quantity' ||
                    _selectedCompletionMethod == 'minutes')
                  QuantityInput(
                    controller: _targetQuantityController,
                    labelText:
                        _selectedCompletionMethod == 'quantity'
                            ? 'Quantidade Alvo (ex: 1x, 2x)'
                            : 'Minutos Alvo (ex: 200min)',
                    onChanged: (value) {
                      if (!_formChanged) setState(() => _formChanged = true);
                    },
                    validator: (value) {
                      if ((_selectedCompletionMethod == 'quantity' ||
                              _selectedCompletionMethod == 'minutes') &&
                          (value == null || value.isEmpty)) {
                        return 'Este campo é obrigatório para este tipo de completude.';
                      }
                      if (value != null &&
                          value.isNotEmpty &&
                          int.tryParse(value) == null)
                        return 'Por favor, insira um número válido.';
                      return null;
                    },
                  ),

                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 10),
                Text(
                  'Lembretes',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SwitchListTile(
                  title: const Text('Ativar Lembretes'),
                  value: _reminderEnabled,
                  onChanged: (bool value) {
                    setState(() {
                      _reminderEnabled = value;
                      _formChanged = true;
                    });
                  },
                ),
                if (_reminderEnabled) ...[
                  ListTile(
                    title: const Text('Horário do Lembrete'),
                    subtitle: Text(
                      _selectedReminderTime == null
                          ? 'Não definido'
                          : _selectedReminderTime!.format(context),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 18),
                    onTap: () => _selectReminderTime(context),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4.0),
                      side: BorderSide(
                        color:
                            Theme.of(
                              context,
                            ).inputDecorationTheme.border?.borderSide.color ??
                            Colors.grey,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 8.0,
                      horizontal: 12.0,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Repetir em:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    children: List<Widget>.generate(_dayKeys.length, (
                      int index,
                    ) {
                      return FilterChip(
                        label: Text(_dayDisplayNames[index]),
                        selected: _selectedReminderDays[_dayKeys[index]]!,
                        onSelected: (bool selected) {
                          setState(() {
                            _selectedReminderDays[_dayKeys[index]] = selected;
                            _formChanged = true;
                          });
                        },
                      );
                    }),
                  ),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
        persistentFooterButtons: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: ElevatedButton(
              onPressed: _submitHabit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                textStyle: const TextStyle(fontSize: 16),
              ),
              child: Text(buttonText),
            ),
          ),
        ],
      ),
    );
  }
}

class QuantityInput extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final ValueChanged<String> onChanged;
  final FormFieldValidator<String>? validator;

  const QuantityInput({
    super.key,
    required this.controller,
    required this.labelText,
    required this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      // Garante que o Row e seus filhos tenham a mesma altura
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 8.0,
        ), // Adiciona padding vertical se necessário
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment
                  .stretch, // Faz os filhos esticarem verticalmente
          children: [
            Expanded(
              child: TextFormField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: labelText,
                  border: const OutlineInputBorder(),
                ),
                validator: validator,
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.grey.shade400,
                ), // Adapte a cor ao tema
                borderRadius: BorderRadius.circular(4.0),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    // Define largura para os botões
                    width: 48, // Ajuste conforme necessário
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(3.0),
                            bottomLeft: Radius.circular(3.0),
                          ),
                        ),
                      ),
                      onPressed: () {
                        int currentValue = int.tryParse(controller.text) ?? 0;
                        if (currentValue > 0) {
                          // Impede valores negativos
                          controller.text = (currentValue - 1).toString();
                          onChanged(controller.text);
                        }
                      },
                      child: const Icon(Icons.remove, size: 20),
                    ),
                  ),
                  Container(width: 1, color: Colors.grey.shade300), // Divisor
                  SizedBox(
                    width: 48,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            topRight: Radius.circular(3.0),
                            bottomRight: Radius.circular(3.0),
                          ),
                        ),
                      ),
                      onPressed: () {
                        int currentValue = int.tryParse(controller.text) ?? 0;
                        controller.text = (currentValue + 1).toString();
                        onChanged(controller.text);
                      },
                      child: const Icon(Icons.add, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

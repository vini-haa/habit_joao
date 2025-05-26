// frontend/lib/widgets/habit_card_with_heatmap.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';
import 'package:frontend/models/habit.dart';
import 'package:frontend/models/habit_record.dart';

class HabitCardWithHeatmap extends StatefulWidget {
  final Habit habit;
  final VoidCallback
  onHabitModified; // Callback para quando um hábito é modificado/registrado/deletado
  final Function(Habit) onCheckButtonPressed; // Callback para o botão de check
  final bool
  showDetails; // NOVO: Controla se detalhes como Alvo, Progresso e Streak devem ser exibidos

  const HabitCardWithHeatmap({
    super.key,
    required this.habit,
    required this.onHabitModified,
    required this.onCheckButtonPressed,
    this.showDetails =
        true, // Default para true, para não quebrar a HabitListScreen (se fosse usar lá)
  });

  @override
  State<HabitCardWithHeatmap> createState() => _HabitCardWithHeatmapState();
}

class _HabitCardWithHeatmapState extends State<HabitCardWithHeatmap> {
  final String _baseUrl = 'http://10.0.2.2:5000';

  Map<DateTime, int> _datasets = {};
  bool _isLoadingHeatmap = true;
  String? _heatmapErrorMessage;

  @override
  void initState() {
    super.initState();
    _fetchHabitRecordsForHeatmap();
  }

  @override
  void didUpdateWidget(covariant HabitCardWithHeatmap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.habit.id != widget.habit.id ||
        oldWidget.habit.isCompletedToday != widget.habit.isCompletedToday ||
        oldWidget.habit.currentPeriodQuantity !=
            widget.habit.currentPeriodQuantity) {
      _fetchHabitRecordsForHeatmap();
    }
  }

  Future<void> _fetchHabitRecordsForHeatmap() async {
    setState(() {
      _isLoadingHeatmap = true;
      _heatmapErrorMessage = null;
      _datasets = {}; // Limpa dados antigos enquanto carrega novos
    });

    try {
      final DateTime today = DateTime.now();
      final DateTime sixMonthsAgo = DateTime(
        today.year,
        today.month - 5,
        today.day,
      ); // 6 meses atrás

      final String apiUrl =
          '$_baseUrl/habits/${widget.habit.id}/records?' +
          'start_date=${sixMonthsAgo.toIso8601String().split('T')[0]}&' +
          'end_date=${today.toIso8601String().split('T')[0]}';

      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        List<dynamic> jsonList = jsonDecode(response.body);
        Map<DateTime, int> newDatasets = {};

        for (var json in jsonList) {
          HabitRecord record = HabitRecord.fromJson(json);
          DateTime normalizedDate = DateTime(
            record.recordDate.year,
            record.recordDate.month,
            record.recordDate.day,
          );
          newDatasets[normalizedDate] =
              (newDatasets[normalizedDate] ?? 0) +
              (record.quantityCompleted ?? 1);
        }

        if (mounted) {
          setState(() {
            _datasets = newDatasets;
            _isLoadingHeatmap = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _heatmapErrorMessage =
                'Falha ao carregar heatmap: ${response.statusCode}';
            _isLoadingHeatmap = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _heatmapErrorMessage = 'Erro de conexão ao carregar heatmap: $e';
          _isLoadingHeatmap = false;
        });
      }
    }
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
                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hábito excluído com sucesso!')),
          );
          widget
              .onHabitModified(); // Notifica a lista que um hábito foi modificado
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao excluir hábito: ${response.body}')),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro de conexão ao excluir: $e')),
        );
      }
    }
  }

  // NOVA FUNÇÃO ADICIONADA
  Future<void> _undoTodayRecord(int habitId) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Limpar Registro de Hoje?'),
        content: const Text(
            'Tem certeza que deseja limpar o progresso registrado hoje para este hábito?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  jsonDecode(response.body)['message'] ?? 'Registro de hoje limpo com sucesso!')),
        );
        if (mounted) {
          widget.onHabitModified(); // Notifica para recarregar
        }
      } else {
        final errorData = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao limpar registro: ${errorData['error'] ?? response.body}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro de conexão ao limpar registro: $e')),
      );
    }
  }

  Widget _buildTargetText(Habit habit) {
    if (habit.targetQuantity != null) {
      return Text(
        'Alvo: ${habit.targetQuantity} ${habit.completionMethod == 'minutes' ? 'min' : 'x'}',
        style: TextStyle(
          fontSize: 14,
          color: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withOpacity(0.8),
        ), // Usar cor do tema
      );
    } else if (habit.targetDaysPerWeek != null) {
      return Text(
        'Alvo: ${habit.targetDaysPerWeek} dias no período',
        style: TextStyle(
          fontSize: 14,
          color: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withOpacity(0.8),
        ), // Usar cor do tema
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    // bool isCheckButtonDisabled = widget.habit.isCompletedToday; // Linha original removida/modificada

    // Lógica para determinar se o botão principal está desabilitado para TAP
    bool disableMainButtonTap;
    if (widget.habit.completionMethod == 'boolean') {
      disableMainButtonTap = widget.habit.isCompletedToday;
    } else { // 'quantity' ou 'minutes'
      disableMainButtonTap = false; // Sempre permite TAP para adicionar mais
    }

    // Lógica para aparência visual de "completo"
    bool isConsideredVisuallyComplete = widget.habit.isCompletedToday;
    IconData mainButtonIcon = Icons.check_rounded;

    if (widget.habit.completionMethod == 'quantity' || widget.habit.completionMethod == 'minutes') {
      final bool targetExists = widget.habit.targetQuantity != null && widget.habit.targetQuantity! > 0;
      final bool hasProgress = widget.habit.currentPeriodQuantity != null && widget.habit.currentPeriodQuantity! > 0;

      if (targetExists) { // Se existe uma meta
          isConsideredVisuallyComplete = (widget.habit.currentPeriodQuantity ?? 0) >= widget.habit.targetQuantity!;
          if (hasProgress && !isConsideredVisuallyComplete) {
            mainButtonIcon = Icons.add_circle_outline; // Meta não atingida, mas tem progresso
          } else if (!hasProgress) {
            mainButtonIcon = Icons.check_rounded; // Sem progresso ainda, ícone de check
          } else {
            mainButtonIcon = Icons.check_rounded; // Meta atingida
          }
      } else if (hasProgress) { // Sem meta, mas com progresso
          isConsideredVisuallyComplete = true; // Considera visualmente completo
          mainButtonIcon = Icons.check_rounded;
      } else { // Sem meta e sem progresso
          isConsideredVisuallyComplete = false;
          mainButtonIcon = Icons.check_rounded;
      }
    }


    // Heatmap colors - manter os tons de verde para o heatmap
    Color githubLightGreen = Colors.green.shade200;
    Color githubMediumGreen = Colors.green.shade500;
    Color githubDarkGreen = Colors.green.shade800;
    Color githubVeryDarkGreen = Colors.green.shade900;
    Color defaultDayColor =
        Colors.grey.shade400; // Changed to a darker grey for better contrast

    final DateTime heatmapStartDate = DateTime(
      DateTime.now().year,
      DateTime.now().month - 5,
      1,
    ); // 6 meses atrás
    final DateTime heatmapEndDate = DateTime.now();

    // Lógica para a barra de progresso visual
    double progress = 0.0;
    String progressText = '';
    bool showProgressBar = false;

    if (widget.habit.completionMethod == 'quantity' ||
        widget.habit.completionMethod == 'minutes') {
      if (widget.habit.targetQuantity != null &&
          widget.habit.targetQuantity! > 0) {
        progress =
            (widget.habit.currentPeriodQuantity ?? 0) /
            widget.habit.targetQuantity!;
        progress = progress.clamp(
          0.0,
          1.0,
        ); // Garante que o progresso esteja entre 0 e 1
        progressText =
            '${widget.habit.currentPeriodQuantity ?? 0} / ${widget.habit.targetQuantity} ${widget.habit.completionMethod == 'minutes' ? 'min' : 'x'}';
        showProgressBar = true;
      }
    } else if (widget.habit.countMethod == 'weekly' ||
        widget.habit.countMethod == 'monthly') {
      if (widget.habit.targetDaysPerWeek != null &&
          widget.habit.targetDaysPerWeek! > 0) {
        progress =
            (widget.habit.currentPeriodDaysCompleted ?? 0) /
            widget.habit.targetDaysPerWeek!;
        progress = progress.clamp(0.0, 1.0);
        progressText =
            '${widget.habit.currentPeriodDaysCompleted ?? 0} / ${widget.habit.targetDaysPerWeek} dias';
        showProgressBar = true;
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      color:
          Theme.of(
            context,
          ).colorScheme.surfaceVariant, // Cor do tema para o fundo do card
      child: Padding(
        padding: const EdgeInsets.only(
          top: 16.0,
          left: 16.0,
          right: 16.0,
          bottom: 8.0,
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    right: widget.showDetails ? 56.0 : 4.0,
                  ), // Ajusta padding se não mostrar detalhes
                  child: Text(
                    widget.habit.name,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color:
                          Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant, // Cor do tema para o nome do hábito
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 4),
                if (widget.habit.categories.isNotEmpty &&
                    widget
                        .showDetails) // Oculta categorias se showDetails for false
                  Wrap(
                    spacing: 4.0,
                    runSpacing: 0.0,
                    children:
                        widget.habit.categories
                            .map(
                              (cat) => Chip(
                                label: Text(cat.name),
                                padding: EdgeInsets.zero,
                                labelPadding: const EdgeInsets.symmetric(
                                  horizontal: 6.0,
                                ),
                                visualDensity: VisualDensity.compact,
                                labelStyle: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withOpacity(0.8), // Cor do texto do chip
                                ),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                backgroundColor:
                                    Theme.of(context)
                                        .colorScheme
                                        .background, // Fundo do chip levemente diferente
                                side: BorderSide(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.outlineVariant,
                                ), // Borda sutil
                              ),
                            )
                            .toList(),
                  ),
                const SizedBox(height: 8),

                // ESCONDE DETALHES SE showDetails FOR FALSO
                if (widget.showDetails) ...[
                  if (showProgressBar) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Progresso: $progressText',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withOpacity(0.8),
                      ), // Usar cor do tema
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor:
                          Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest, // Fundo da barra de progresso
                      color:
                          Theme.of(
                            context,
                          ).colorScheme.primary, // Cor do progresso
                      borderRadius: BorderRadius.circular(
                        4,
                      ), // Arredondar a barra de progresso
                      minHeight: 8, // Altura da barra
                    ),
                    const SizedBox(height: 4),
                  ] else ...[
                    _buildTargetText(widget.habit),
                    const SizedBox(height: 4),
                    if (widget.habit.completionMethod == 'quantity' ||
                        widget.habit.completionMethod == 'minutes')
                      Text(
                        'Progresso: ${widget.habit.currentPeriodQuantity ?? 0} de ${widget.habit.targetQuantity ?? 'N/A'} ${widget.habit.completionMethod == 'minutes' ? 'min' : 'x'}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant
                              .withOpacity(0.8),
                        ),
                      )
                    else if (widget.habit.countMethod == 'weekly' ||
                        widget.habit.countMethod == 'monthly')
                      Text(
                        'Progresso: ${widget.habit.currentPeriodDaysCompleted ?? 0} de ${widget.habit.targetDaysPerWeek ?? 'N/A'} dias',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant
                              .withOpacity(0.8),
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    'Streak: ${widget.habit.currentStreak} dias',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withOpacity(0.8),
                    ), // Usar cor do tema
                  ),
                  const SizedBox(height: 10),
                ],
                // FIM DA SEÇÃO ESCONDIDA

                // Heatmap individual
                _isLoadingHeatmap
                    ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                    : _heatmapErrorMessage != null
                    ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        _heatmapErrorMessage!, // MODIFICADO: _heatmapErrorMessage já é o erro
                        style: TextStyle(
                          color:
                              Theme.of(
                                context,
                              ).colorScheme.error, // Usar cor de erro do tema
                          fontSize: 12,
                        ),
                      ),
                    )
                    :
                    // Condição para ajustar o padding e o scrollable do heatmap
                    widget
                        .showDetails // Se showDetails for true (na tela de lista simples)
                    ? HeatMap(
                      // Heatmap com menos padding e não scrollable
                      startDate: heatmapStartDate,
                      endDate: heatmapEndDate,
                      datasets: _datasets,
                      colorsets: {
                        1: githubLightGreen,
                        2: githubMediumGreen,
                        4: githubDarkGreen,
                        6: githubVeryDarkGreen,
                      },
                      defaultColor: defaultDayColor,
                      textColor: Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 10, // Tamanho menor para o heatmap dentro do card
                      margin: const EdgeInsets.all(1),
                      borderRadius: 1,
                      scrollable: false, // Não scrollable
                      showText: false,
                      showColorTip: false,
                      onClick: (date) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Dia: ${date.toLocal().toString().split(' ')[0]}, Registros: ${_datasets[date] ?? 0}',
                            ),
                          ),
                        );
                      },
                    )
                    : Padding(
                      // Se showDetails for false (na tela de progresso com heatmap individual)
                      padding: const EdgeInsets.symmetric(
                        vertical: 8.0,
                      ), // Adiciona padding vertical
                      child: HeatMap(
                        // Heatmap ligeiramente maior e scrollable
                        startDate: heatmapStartDate,
                        endDate: heatmapEndDate,
                        datasets: _datasets,
                        colorsets: {
                          1: githubLightGreen,
                          2: githubMediumGreen,
                          4: githubDarkGreen,
                          6: githubVeryDarkGreen,
                        },
                        defaultColor: defaultDayColor,
                        textColor:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                        size: 12, // Tamanho um pouco maior
                        margin: const EdgeInsets.all(2),
                        borderRadius: 2,
                        scrollable: true, // Agora é scrollable
                        showText: false,
                        showColorTip:
                            false,
                        onClick: (date) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Dia: ${date.toLocal().toString().split(' ')[0]}, Registros: ${_datasets[date] ?? 0}',
                              ),
                            ),
                          );
                        },
                      ),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

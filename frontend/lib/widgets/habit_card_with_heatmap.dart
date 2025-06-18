import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';
import 'package:frontend/models/habit.dart';
import 'package:frontend/models/habit_record.dart';
import 'package:visibility_detector/visibility_detector.dart';

class HabitCardWithHeatmap extends StatefulWidget {
  final Habit habit;
  final VoidCallback onHabitModified;
  final Function(Habit) onCheckButtonPressed;
  final bool showDetails;

  const HabitCardWithHeatmap({
    super.key,
    required this.habit,
    required this.onHabitModified,
    required this.onCheckButtonPressed,
    this.showDetails = true,
  });

  @override
  State<HabitCardWithHeatmap> createState() => _HabitCardWithHeatmapState();
}

class _HabitCardWithHeatmapState extends State<HabitCardWithHeatmap> {
  final String _baseUrl = 'http://10.0.2.2:5000';

  Map<DateTime, int> _datasets = {};
  bool _isLoadingHeatmap = false;
  String? _heatmapErrorMessage;
  bool _dataFetchInitiated = false;

  @override
  void didUpdateWidget(covariant HabitCardWithHeatmap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dataFetchInitiated &&
        (oldWidget.habit.id != widget.habit.id ||
            oldWidget.habit.isCompletedToday != widget.habit.isCompletedToday ||
            oldWidget.habit.currentPeriodQuantity !=
                widget.habit.currentPeriodQuantity)) {
      _fetchHabitRecordsForHeatmap();
    }
  }

  Future<void> _fetchHabitRecordsForHeatmap() async {
    if (!mounted) return;
    setState(() {
      _isLoadingHeatmap = true;
      _heatmapErrorMessage = null;
    });

    try {
      final DateTime today = DateTime.now();
      final DateTime sixMonthsAgo = DateTime(
        today.year,
        today.month - 5,
        today.day,
      );
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
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _heatmapErrorMessage =
                'Falha ao carregar heatmap: ${response.statusCode}';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _heatmapErrorMessage = 'Erro de conexão ao carregar heatmap: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingHeatmap = false;
        });
      }
    }
  }

  // Seus outros métodos como _buildTargetText, etc., devem ser colocados aqui se existirem.

  @override
  Widget build(BuildContext context) {
    // Definições de cores e datas para o heatmap
    final DateTime heatmapStartDate = DateTime(
      DateTime.now().year,
      DateTime.now().month - 5,
      1,
    );
    final DateTime heatmapEndDate = DateTime.now();

    return VisibilityDetector(
      key: Key('heatmap_${widget.habit.id}'),
      onVisibilityChanged: (visibilityInfo) {
        if (visibilityInfo.visibleFraction > 0 && !_dataFetchInitiated) {
          setState(() {
            _dataFetchInitiated = true;
          });
          _fetchHabitRecordsForHeatmap();
        }
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        color: Theme.of(context).colorScheme.surfaceVariant,
        child: Padding(
          padding: const EdgeInsets.only(
            top: 16.0,
            left: 16.0,
            right: 16.0,
            bottom: 8.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.habit.name,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),

              // ... (qualquer outra UI como categorias, streak, etc. iria aqui) ...
              const SizedBox(height: 10),

              // Lógica de exibição do Heatmap CORRIGIDA
              if (!_dataFetchInitiated)
                const SizedBox(
                  height: 70,
                  child: Center(child: Text("Carregando heatmap...")),
                )
              else if (_isLoadingHeatmap)
                const SizedBox(
                  height: 70,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_heatmapErrorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    _heatmapErrorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                )
              else
                // CORREÇÃO: O widget HeatMap agora tem todos os parâmetros necessários.
                HeatMap(
                  startDate: heatmapStartDate,
                  endDate: heatmapEndDate,
                  datasets: _datasets,
                  defaultColor: Colors.grey.shade400,
                  // O parâmetro que faltava:
                  colorsets: {
                    1: Colors.green.shade200,
                    2: Colors.green.shade500,
                    4: Colors.green.shade800,
                    6: Colors.green.shade900,
                  },
                  textColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 10,
                  margin: const EdgeInsets.all(1),
                  borderRadius: 1,
                  scrollable: widget.showDetails ? false : true,
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
                ),
            ],
          ),
        ),
      ),
    );
  }
}

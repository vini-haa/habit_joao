// frontend/lib/screens/habit_heatmap_screen.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';

import 'package:frontend/models/habit.dart';
import 'package:frontend/models/habit_record.dart';

class HabitHeatmapScreen extends StatefulWidget {
  final Habit habit;

  const HabitHeatmapScreen({super.key, required this.habit});

  @override
  State<HabitHeatmapScreen> createState() => _HabitHeatmapScreenState();
}

class _HabitHeatmapScreenState extends State<HabitHeatmapScreen> {
  final String _baseUrl =
      'http://10.0.2.2:5000'; // ATENÇÃO: Ajuste este IP se estiver em dispositivo físico.

  Map<DateTime, int> _datasets = {};
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchHabitRecords();
  }

  Future<void> _fetchHabitRecords() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final DateTime today = DateTime.now();
      final DateTime oneYearAgo = DateTime(
        today.year - 1,
        today.month,
        today.day,
      );

      final String apiUrl =
          '$_baseUrl/habits/${widget.habit.id}/records?' +
          'start_date=${oneYearAgo.toIso8601String().split('T')[0]}&' +
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

        setState(() {
          _datasets = newDatasets;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage =
              'Falha ao carregar histórico: ${response.statusCode} - ${response.body}';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro de conexão ao carregar histórico: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Color githubLightGreen = Colors.green.shade200;
    Color githubMediumGreen = Colors.green.shade500;
    Color githubDarkGreen = Colors.green.shade800;
    Color githubVeryDarkGreen = Colors.green.shade900;

    Color defaultDayColor = Colors.grey.shade700; // Changed to a darker grey

    final DateTime heatmapStartDate = DateTime(
      DateTime.now().year - 1,
      DateTime.now().month,
      DateTime.now().day,
    );
    final DateTime heatmapEndDate = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text('Progresso: ${widget.habit.name}'),
        backgroundColor: Colors.grey.shade900, // Darker background for AppBar
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.grey.shade900, // Darker background for the screen
      body:
          _isLoading
              ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
              : _errorMessage != null
              ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 16,
                    ),
                  ),
                ),
              )
              : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Histórico de Conclusões',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 20),
                      HeatMap(
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
                        textColor: Colors.white,
                        size: 14,
                        margin: const EdgeInsets.all(2),
                        borderRadius: 2,
                        scrollable: true,
                        showText: false,
                        showColorTip: true,
                        colorTipHelper: const [
                          Text(
                            'Nenhum',
                            style: TextStyle(color: Colors.white, fontSize: 10),
                          ),
                          Text(
                            'Pouco',
                            style: TextStyle(color: Colors.white, fontSize: 10),
                          ),
                          Text(
                            'Médio',
                            style: TextStyle(color: Colors.white, fontSize: 10),
                          ),
                          Text(
                            'Muito',
                            style: TextStyle(color: Colors.white, fontSize: 10),
                          ),
                          Text(
                            'Mais',
                            style: TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ],
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
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
    );
  }
}

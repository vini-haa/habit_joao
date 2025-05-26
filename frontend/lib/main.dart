// frontend/lib/main.dart
import 'package:flutter/material.dart';

// IMPORTS ESSENCIAIS - VERIFIQUE ESTES CAMINHOS E NOMES DE ARQUIVO CUIDADOSAMENTE:
import 'package:frontend/screens/habit_list_screen.dart';
import 'package:frontend/screens/habit_progress_list_screen.dart';
// --- FIM DOS IMPORTS CRÍTICOS ---

import 'package:frontend/services/notification_service.dart';
import 'package:frontend/screens/habit_form_screen.dart';

// SE OverallProgressScreen AINDA USA ESTES, MANTENHA-OS:
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Presumindo que NotificationService agora é encontrado e funciona:
  await NotificationService().init();
  await NotificationService().requestIOSPermissions();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Habit Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const MainScreen(),
    );
  }
}

// OverallProgressScreen
class OverallProgressScreen extends StatefulWidget {
  const OverallProgressScreen({super.key});
  @override
  State<OverallProgressScreen> createState() => _OverallProgressScreenState();
}

class _OverallProgressScreenState extends State<OverallProgressScreen> {
  final String _baseUrl =
      'http://10.0.2.2:5000'; // Ou seu IP se testando em dispositivo físico
  Map<DateTime, int> _overallDatasets = {};
  bool _isLoadingOverallProgress = true;
  String? _overallErrorMessage;

  @override
  void initState() {
    super.initState();
    _fetchOverallProgressData();
  }

  void fetchOverallProgressDataPublic() {
    _fetchOverallProgressData();
  }

  Future<void> _fetchOverallProgressData() async {
    if (!mounted) return;
    setState(() {
      _isLoadingOverallProgress = true;
      _overallErrorMessage = null;
    });
    try {
      final DateTime today = DateTime.now();
      final DateTime oneYearAgo = DateTime(
        today.year - 1,
        today.month,
        today.day,
      );
      final String apiUrl =
          '$_baseUrl/all_habit_records?start_date=${oneYearAgo.toIso8601String().split('T')[0]}&end_date=${today.toIso8601String().split('T')[0]}';
      final response = await http.get(Uri.parse(apiUrl));
      if (!mounted) return;
      if (response.statusCode == 200) {
        List<dynamic> jsonList = jsonDecode(response.body);
        Map<DateTime, int> aggregatedDatasets = {};
        for (var json in jsonList) {
          DateTime recordDate = DateTime.parse(json['record_date'] as String);
          DateTime normalizedDate = DateTime(
            recordDate.year,
            recordDate.month,
            recordDate.day,
          );
          int quantity = json['quantity_completed'] as int? ?? 1;
          aggregatedDatasets[normalizedDate] =
              (aggregatedDatasets[normalizedDate] ?? 0) + quantity;
        }
        setState(() {
          _overallDatasets = aggregatedDatasets;
          _isLoadingOverallProgress = false;
        });
      } else {
        setState(() {
          _overallErrorMessage =
              'Falha ao carregar progresso geral: ${response.statusCode} - ${response.body}';
          _isLoadingOverallProgress = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _overallErrorMessage =
            'Erro de conexão ao carregar progresso geral: $e';
        _isLoadingOverallProgress = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Color githubLightGreen = Colors.green.shade200;
    Color githubMediumGreen = Colors.green.shade500;
    Color githubDarkGreen = Colors.green.shade800;
    Color githubVeryDarkGreen = Colors.green.shade900;
    Color defaultDayColor =
        Theme.of(context).colorScheme.surfaceContainerHighest;

    final DateTime heatmapStartDate = DateTime(
      DateTime.now().year - 1,
      DateTime.now().month,
      DateTime.now().day,
    );
    final DateTime heatmapEndDate = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Progresso Geral'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchOverallProgressData,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Visão Geral',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total de Registros',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        _overallDatasets.values
                            .fold(0, (sum, element) => sum + element)
                            .toString(),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Text(
              'Atividade Diária (Todos os Hábitos)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child:
                _isLoadingOverallProgress
                    ? const Center(child: CircularProgressIndicator())
                    : _overallErrorMessage != null
                    ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          _overallErrorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    )
                    : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      scrollDirection: Axis.horizontal,
                      child: HeatMap(
                        startDate: heatmapStartDate,
                        endDate: heatmapEndDate,
                        datasets: _overallDatasets,
                        colorsets: {
                          1: githubLightGreen,
                          2: githubMediumGreen,
                          4: githubDarkGreen,
                          6: githubVeryDarkGreen,
                        },
                        defaultColor: defaultDayColor,
                        textColor: Theme.of(context).colorScheme.onSurface,
                        size: 16,
                        margin: const EdgeInsets.all(2.5),
                        borderRadius: 3,
                        scrollable: true,
                        showText: false,
                        showColorTip: true,
                        colorTipHelper: [
                          Text(
                            ' Nenhum',
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            ' Pouco',
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            ' Médio',
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            ' Muito',
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            ' Mais',
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                        onClick: (date) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Dia: ${date.toLocal().toString().split(' ')[0]}, Atividade Total: ${_overallDatasets[date] ?? 0}',
                              ),
                            ),
                          );
                        },
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  // Estas GlobalKeys precisam que _HabitListScreenState e _HabitProgressListScreenState
  // sejam tipos conhecidos, o que requer os imports corretos no TOPO DESTE ARQUIVO.
  final GlobalKey<_HabitListScreenState> _habitListKey =
      GlobalKey<_HabitListScreenState>();
  final GlobalKey<_HabitProgressListScreenState> _habitProgressListKey =
      GlobalKey<_HabitProgressListScreenState>();
  final GlobalKey<_OverallProgressScreenState> _overallProgressKey =
      GlobalKey<_OverallProgressScreenState>();

  late final List<Widget> _widgetOptions;

  @override
  void initState() {
    super.initState();
    _widgetOptions = <Widget>[
      HabitListScreen(key: _habitListKey),
      HabitProgressListScreen(key: _habitProgressListKey),
      OverallProgressScreen(key: _overallProgressKey),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    if (index == 0) {
      _habitListKey.currentState?.refreshHabits();
    } else if (index == 1) {
      _habitProgressListKey.currentState?.refreshHabits();
    } else if (index == 2) {
      _overallProgressKey.currentState?.fetchOverallProgressDataPublic();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _widgetOptions),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt_outlined),
            activeIcon: Icon(Icons.list_alt),
            label: 'Hábitos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.timeline_outlined),
            activeIcon: Icon(Icons.timeline),
            label: 'Progresso',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.insights_outlined),
            activeIcon: Icon(Icons.insights),
            label: 'Geral',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Theme.of(
          context,
        ).colorScheme.onSurfaceVariant.withOpacity(0.7),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        type: BottomNavigationBarType.fixed,
      ),
      floatingActionButton:
          _selectedIndex == 0
              ? FloatingActionButton.large(
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const HabitFormScreen(),
                    ),
                  );
                  if (result == true && mounted && _selectedIndex == 0) {
                    _habitListKey.currentState?.refreshHabits();
                  }
                },
                child: const Icon(Icons.add_rounded),
              )
              : null,
    );
  }
}

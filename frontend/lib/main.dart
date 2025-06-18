// lib/main.dart
import 'package:flutter/material.dart';
// As importações de http, dart:convert e flutter_heatmap_calendar
// são usadas em OverallProgressScreen, que foi movida para cá.
// Se OverallProgressScreen for separada novamente, essas importações
// podem ser movidas para o arquivo dela.
import 'package:http/http.dart'
    as http;
import 'dart:convert';
import 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';

import 'package:frontend/screens/habit_list_screen.dart';
import 'package:frontend/screens/habit_progress_list_screen.dart';
import 'package:frontend/screens/habit_form_screen.dart';

void main() {
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
        // AppBarTheme global removida daqui, pois cada SliverAppBar
        // controlará sua própria aparência (especialmente a cor de fundo
        // que se mistura com o scaffoldBackgroundColor quando scrollado).
      ),
      home: const MainScreen(),
    );
  }
}

// OverallProgressScreen (mantida aqui para simplicidade, mas poderia ser um arquivo separado)
// Esta tela NÃO usará o SliverAppBar.large por enquanto, para manter o foco nas telas de lista.
class OverallProgressScreen extends StatefulWidget {
  const OverallProgressScreen({super.key});

  @override
  State<OverallProgressScreen> createState() => _OverallProgressScreenState();
}

class _OverallProgressScreenState extends State<OverallProgressScreen> {
  final String _baseUrl =
      'http://10.0.2.2:5000';
  Map<DateTime, int> _overallDatasets = {};
  bool _isLoadingOverallProgress = true;
  String? _overallErrorMessage;

  @override
  void initState() {
    super.initState();
    _fetchOverallProgressData();
  }

  Future<void> _fetchOverallProgressData() async {
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
          '$_baseUrl/all_habit_records?' +
          'start_date=${oneYearAgo.toIso8601String().split('T')[0]}&' +
          'end_date=${today.toIso8601String().split('T')[0]}';

      final response = await http.get(Uri.parse(apiUrl));

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
          int quantity =
              json['quantity_completed'] as int? ??
              1;

          aggregatedDatasets[normalizedDate] =
              (aggregatedDatasets[normalizedDate] ?? 0) + quantity;
        }

        if (mounted) {
          setState(() {
            _overallDatasets = aggregatedDatasets;
            _isLoadingOverallProgress = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _overallErrorMessage =
                'Falha ao carregar progresso geral: ${response.statusCode} - ${response.body}';
            _isLoadingOverallProgress = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _overallErrorMessage =
              'Erro de conexão ao carregar progresso geral: $e';
          _isLoadingOverallProgress = false;
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
    Color defaultDayColor =
        Colors
            .grey
            .shade300;

    final DateTime heatmapStartDate = DateTime(
      DateTime.now().year - 1,
      DateTime.now().month,
      DateTime.now().day,
    );
    final DateTime heatmapEndDate = DateTime.now();

    return Scaffold(
      backgroundColor:
          Theme.of(
            context,
          ).colorScheme.surface,
      appBar: AppBar( // AppBar normal para esta tela
        title: const Text('Progresso Geral'),
        backgroundColor: Theme.of(context).colorScheme.surfaceVariant, // Cor de fundo para AppBar normal
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              Icons.refresh,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
                const Text(
                  'Visão Geral',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context)
                            .colorScheme
                            .surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total de Registros',
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        _overallDatasets.values
                            .fold(0, (sum, element) => sum + element)
                            .toString(),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
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
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'Atividade Diária (Todos os Hábitos)',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
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
                        textColor:
                            Colors
                                .black87,
                        size: 14,
                        margin: const EdgeInsets.all(2),
                        borderRadius: 2,
                        scrollable: true,
                        showText: false,
                        showColorTip: true,
                        colorTipHelper: const [
                          Text('Nenhum', style: TextStyle(color: Colors.black87, fontSize: 10)),
                          Text('Pouco', style: TextStyle(color: Colors.black87, fontSize: 10)),
                          Text('Médio', style: TextStyle(color: Colors.black87, fontSize: 10)),
                          Text('Muito', style: TextStyle(color: Colors.black87, fontSize: 10)),
                          Text('Mais', style: TextStyle(color: Colors.black87, fontSize: 10)),
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

  // As telas agora são instanciadas diretamente aqui para simplificar,
  // mas em um app maior, você poderia usar chaves globais para
  // chamar métodos de refresh nelas, se necessário.
  static final List<Widget> _widgetOptions = <Widget>[
    const HabitListScreen(),
    const HabitProgressListScreen(),
    const OverallProgressScreen(), // Adicionando a terceira tela
  ];

  // Títulos para as AppBars de cada tela
  static const List<String> _appBarTitles = <String>[
    'Meus Hábitos',
    'Progresso dos Hábitos',
    'Visão Geral', // Título para a nova aba
  ];


  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _widgetOptions,
      ),
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
        selectedItemColor: Theme.of(context).colorScheme.primary,
        onTap: _onItemTapped,
        backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
        unselectedItemColor:
            Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
        type: BottomNavigationBarType.fixed,
      ),
      // Condiciona a exibição do FAB
      floatingActionButton: _selectedIndex == 0 // Exibe o FAB apenas se o índice for 0 (tela "Hábitos")
          ? FloatingActionButton.large(
              onPressed: () async {
                // A navegação para HabitFormScreen deve funcionar como antes
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const HabitFormScreen()),
                );
                // Para atualizar a HabitListScreen após adicionar um hábito:
                // A HabitListScreen já tem um _loadAllHabitsAndSetupFilters no initState.
                // Se a navegação de volta causar um rebuild ou se você tiver um
                // mecanismo de callback/provider, ela pode se atualizar.
                // Uma forma simples de tentar forçar um refresh na HabitListScreen
                // se ela estiver visível (_selectedIndex == 0) é chamar setState aqui,
                // o que reconstrói o MainScreen e, por consequência, o IndexedStack
                // pode reconstruir seu filho atual.
                // No entanto, a melhor prática seria a HabitListScreen escutar
                // por mudanças ou ser explicitamente atualizada.
                if (mounted && _selectedIndex == 0) {
                    // Se HabitListScreen tiver uma GlobalKey e um método de refresh,
                    // você poderia chamá-lo.
                    // Ex: habitListScreenKey.currentState?.refreshHabits();
                    // Por ora, um setState() no MainScreen pode ser suficiente
                    // se a HabitListScreen se reconstituir adequadamente.
                    // Como _widgetOptions contém const HabitListScreen(), ela será
                    // reconstruída se MainScreen for reconstruída.
                  setState(() {});
                }
              },
              child: const Icon(Icons.add_rounded),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onTertiaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28.0),
              ),
              elevation: 4.0,
            )
          : null, // Não exibe FAB para os outros índices
    );
  }
}

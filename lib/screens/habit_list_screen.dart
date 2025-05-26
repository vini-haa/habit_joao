import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/habit.dart'; // Importa o modelo Habit
import 'package:frontend/utils/string_extensions.dart'; // Importa a extensão capitalize

class HabitListScreen extends StatefulWidget {
  const HabitListScreen({super.key});

  @override
  State<HabitListScreen> createState() => _HabitListScreenState();
}

class _HabitListScreenState extends State<HabitListScreen> {
  late Future<List<Habit>>
  futureHabits; // Futuro que conterá a lista de hábitos

  @override
  void initState() {
    super.initState();
    futureHabits =
        fetchHabits(); // Inicia a busca pelos hábitos quando a tela é criada
  }

  Future<List<Habit>> fetchHabits() async {
    final String apiUrl =
        'http://10.0.2.2:5000/habits'; // A mesma URL do backend
    try {
      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        // Se o servidor retornar um status OK (200),
        // parseie o JSON e mapeie para uma lista de objetos Habit.
        List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList.map((json) => Habit.fromJson(json)).toList();
      } else {
        // Se o servidor retornar uma resposta de erro,
        // lance uma exceção.
        throw Exception('Falha ao carregar hábitos: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Falha ao conectar com o backend: $e');
    }
  }

  // Função para registrar a completude do hábito
  Future<void> _recordHabitCompletion(
    int habitId,
    String completionMethod, {
    int? quantityCompleted,
  }) async {
    final String apiUrl = 'http://10.0.2.2:5000/habit_records';
    final String recordDate =
        DateTime.now().toIso8601String().split(
          'T',
        )[0]; // Data atual no formato<ctrl42>-MM-DD

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hábito registrado com sucesso!')),
        );
        // Recarrega a lista de hábitos após um registro bem-sucedido para atualizar o status visual
        setState(() {
          futureHabits = fetchHabits();
        });
      } else if (response.statusCode == 409) {
        // Conflito (já registrado hoje)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hábito já registrado para hoje!')),
        );
      } else {
        final errorData = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao registrar hábito: ${errorData['error']}'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro de conexão ao registrar: $e')),
      );
    }
  }

  // Função para mostrar o diálogo de entrada de quantidade/minutos
  Future<void> _showQuantityDialog(Habit habit) async {
    TextEditingController quantityController = TextEditingController();
    final _formKeyDialog =
        GlobalKey<FormState>(); // Chave para validar o formulário no diálogo

    return showDialog<void>(
      context: context,
      barrierDismissible: false, // O usuário deve tocar no botão
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Registrar ${habit.name}'),
          content: SingleChildScrollView(
            child: Form(
              // Adiciona um Form para validação no diálogo
              key: _formKeyDialog,
              child: ListBody(
                children: <Widget>[
                  TextFormField(
                    controller: quantityController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText:
                          habit.completionMethod == 'quantity'
                              ? 'Quantidade realizada'
                              : 'Minutos realizados',
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor, insira um valor';
                      }
                      if (int.tryParse(value) == null) {
                        return 'Por favor, insira um número válido';
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
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Registrar'),
              onPressed: () {
                if (_formKeyDialog.currentState!.validate()) {
                  // Valida o formulário antes de registrar
                  _recordHabitCompletion(
                    habit.id,
                    habit.completionMethod,
                    quantityCompleted: int.parse(quantityController.text),
                  );
                  Navigator.of(context).pop(); // Fecha o diálogo
                }
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus Hábitos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                futureHabits = fetchHabits(); // Recarrega a lista de hábitos
              });
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Habit>>(
        future: futureHabits,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // Enquanto espera, mostra um indicador de progresso
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            // Se ocorrer um erro, mostra uma mensagem
            return Center(child: Text('Erro: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            // Se não houver dados, mostra uma mensagem de "nenhum hábito"
            return const Center(child: Text('Nenhum hábito cadastrado ainda.'));
          } else {
            // Se houver dados, exibe a lista de hábitos
            return ListView.builder(
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                Habit habit = snapshot.data![index];
                return Card(
                  margin: const EdgeInsets.all(8.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          // ENVOLVE O NOME DO HÁBITO E O INDICADOR DE STATUS EM UM ROW
                          children: [
                            Expanded(
                              child: Text(
                                habit.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            // Indicador de status de completude hoje usando operador ternário
                            habit.isCompletedToday
                                ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 24.0,
                                )
                                : const Icon(
                                  Icons.radio_button_unchecked,
                                  color: Colors.grey,
                                  size: 24.0,
                                ),
                          ],
                        ),
                        if (habit.description != null &&
                            habit.description!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(habit.description!),
                          ),
                        const SizedBox(height: 8.0),
                        Text(
                          'Método de Contagem: ${habit.countMethod.capitalize()}',
                        ),
                        Text(
                          'Método de Completude: ${habit.completionMethod.capitalize()}',
                        ),
                        if (habit.targetQuantity != null)
                          Text(
                            'Alvo: ${habit.targetQuantity} ${habit.completionMethod == 'minutes' ? 'min' : 'x'}',
                          ),
                        if (habit.targetDaysPerWeek != null)
                          Text(
                            'Dias na Semana/Mês: ${habit.targetDaysPerWeek}',
                          ),

                        // Exibir última data de completude usando operador ternário
                        habit.lastCompletedDate != null
                            ? Text(
                              'Última Conclusão: ${habit.lastCompletedDate}',
                            )
                            : const Text('Última Conclusão: N/A'),

                        // NOVO: Exibir progresso do período (semanal/mensal ou quantidade/minutos)
                        // Usando operador ternário aninhado para lidar com 'else if'
                        habit.completionMethod == 'quantity' ||
                                habit.completionMethod == 'minutes'
                            ? Text(
                              'Progresso Período: ${habit.currentPeriodQuantity ?? 0} de ${habit.targetQuantity ?? 'N/A'} ${habit.completionMethod == 'minutes' ? 'min' : 'x'}',
                            )
                            : (habit.countMethod == 'weekly' ||
                                    habit.countMethod == 'monthly'
                                ? Text(
                                  'Dias Completos: ${habit.currentPeriodDaysCompleted ?? 0} de ${habit.targetDaysPerWeek ?? 'N/A'} dias',
                                )
                                : const SizedBox.shrink()), // Exibe um widget vazio se nenhuma condição for atendida

                        Text(
                          'Criado em: ${habit.createdAt.split(' ')[0]}',
                        ), // Mostra apenas a data
                        // Botão para marcar como feito
                        const SizedBox(height: 10.0), // Espaçamento
                        Align(
                          // Alinha o botão à direita ou no centro
                          alignment: Alignment.bottomRight, // Ou .center
                          child: ElevatedButton.icon(
                            onPressed:
                                habit.isCompletedToday
                                    ? null
                                    : () {
                                      // Desabilita o botão se já foi completado hoje
                                      if (habit.completionMethod ==
                                              'quantity' ||
                                          habit.completionMethod == 'minutes') {
                                        _showQuantityDialog(
                                          habit,
                                        ); // Pede a quantidade/minutos
                                      } else {
                                        _recordHabitCompletion(
                                          habit.id,
                                          habit.completionMethod,
                                        ); // Marca diretamente (para 1x ou outras sem quantidade)
                                      }
                                    },
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Marcar como Feito'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  habit.isCompletedToday
                                      ? Colors.grey[400]
                                      : Colors
                                          .blue, // Cor cinza se desabilitado
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          }
        },
      ),
    );
  }
}

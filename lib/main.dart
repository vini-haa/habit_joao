import 'package:flutter/material.dart';
import 'package:http/http.dart'
    as http; // Importe esta biblioteca para fazer requisições HTTP
import 'dart:convert'; // Importe esta biblioteca para trabalhar com JSON
import 'package:frontend/screens/habit_list_screen.dart'; // Adicione esta linha
import 'package:frontend/utils/string_extensions.dart'; // Adicione esta linha

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Habit Tracker',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HabitFormScreen(), // Define a tela inicial do aplicativo
    );
  }
}

class HabitFormScreen extends StatefulWidget {
  const HabitFormScreen({super.key});

  @override
  _HabitFormScreenState createState() => _HabitFormScreenState();
}

class _HabitFormScreenState extends State<HabitFormScreen> {
  final _formKey = GlobalKey<FormState>(); // Chave para validar o formulário
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _targetQuantityController =
      TextEditingController();
  final TextEditingController _targetDaysPerWeekController =
      TextEditingController();

  String?
  _selectedCountMethod; // Armazena o método de contagem selecionado (diário, semanal, mensal)
  String?
  _selectedCompletionMethod; // Armazena o método de completude selecionado (quantidade, minutos)

  // Listas de opções para os Dropdowns
  final List<String> _countMethods = ['daily', 'weekly', 'monthly'];
  final List<String> _completionMethods = ['quantity', 'minutes'];

  // Função assíncrona para enviar os dados do hábito para o backend
  Future<void> _submitHabit() async {
    // Valida todos os campos do formulário
    if (_formKey.currentState!.validate()) {
      // URL do seu backend Flask.
      // Use 'http://10.0.2.2:5000/habits' para emulador Android
      // Use 'http://localhost:5000/habits' para simulador iOS ou quando rodando o backend diretamente no host e acessando pelo emulador iOS
      // Se estiver em um dispositivo físico, use o IP da sua máquina de desenvolvimento
      final String apiUrl = 'http://10.0.2.2:5000/habits';

      try {
        final response = await http.post(
          Uri.parse(apiUrl),
          headers: <String, String>{
            'Content-Type': 'application/json; charset=UTF-8',
          },
          body: jsonEncode(<String, dynamic>{
            'name': _nameController.text,
            'description':
                _descriptionController.text.isEmpty
                    ? null
                    : _descriptionController.text,
            'count_method': _selectedCountMethod,
            'completion_method': _selectedCompletionMethod,
            // Converte para int ou null se o campo estiver vazio
            'target_quantity':
                _targetQuantityController.text.isEmpty
                    ? null
                    : int.parse(_targetQuantityController.text),
            'target_days_per_week':
                _targetDaysPerWeekController.text.isEmpty
                    ? null
                    : int.parse(_targetDaysPerWeekController.text),
          }),
        );

        // Verifica o código de status da resposta HTTP
        if (response.statusCode == 201) {
          // 201 Created indica sucesso
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hábito adicionado com sucesso!')),
          );
          // Limpa os campos e redefine os seletores após o sucesso
          _nameController.clear();
          _descriptionController.clear();
          _targetQuantityController.clear();
          _targetDaysPerWeekController.clear();
          setState(() {
            _selectedCountMethod = null;
            _selectedCompletionMethod = null;
          });
        } else {
          // Exibe mensagem de erro se a requisição não foi bem-sucedida
          final errorData = jsonDecode(response.body);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao adicionar hábito: ${errorData['error']}'),
            ),
          );
        }
      } catch (e) {
        // Captura erros de conexão ou outros problemas
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro de conexão: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cadastrar Hábito')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            // Usado para permitir rolagem se o conteúdo for muito grande
            children: <Widget>[
              // Campo para o nome do hábito
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nome do Hábito'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor, insira o nome do hábito';
                  }
                  return null;
                },
              ),
              // Campo para a descrição (opcional)
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Descrição (opcional)',
                ),
                maxLines: 3,
              ),
              // Dropdown para o método de contagem (diário, semanal, mensal)
              DropdownButtonFormField<String>(
                value: _selectedCountMethod,
                decoration: const InputDecoration(
                  labelText: 'Método de Contagem',
                ),
                items:
                    _countMethods.map((String method) {
                      return DropdownMenuItem<String>(
                        value: method,
                        child: Text(
                          method.capitalize(),
                        ), // Usa a extensão para capitalizar a primeira letra
                      );
                    }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedCountMethod = newValue;
                  });
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor, selecione o método de contagem';
                  }
                  return null;
                },
              ),
              // Campo condicional para dias alvo, aparece se o método de contagem for semanal ou mensal
              if (_selectedCountMethod == 'weekly' ||
                  _selectedCountMethod == 'monthly')
                TextFormField(
                  controller: _targetDaysPerWeekController,
                  keyboardType: TextInputType.number, // Permite apenas números
                  decoration: const InputDecoration(
                    labelText: 'Dias Alvo por Período (ex: 4 de 7)',
                  ),
                  validator: (value) {
                    if ((_selectedCountMethod == 'weekly' ||
                            _selectedCountMethod == 'monthly') &&
                        (value == null || value.isEmpty)) {
                      return 'Este campo é obrigatório para hábitos semanais/mensais';
                    }
                    if (value != null &&
                        value.isNotEmpty &&
                        int.tryParse(value) == null) {
                      return 'Por favor, insira um número válido';
                    }
                    return null;
                  },
                ),
              // Dropdown para o método de completude (quantidade, minutos)
              DropdownButtonFormField<String>(
                value: _selectedCompletionMethod,
                decoration: const InputDecoration(
                  labelText: 'Método de Completude',
                ),
                items:
                    _completionMethods.map((String method) {
                      return DropdownMenuItem<String>(
                        value: method,
                        child: Text(method.capitalize()),
                      );
                    }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedCompletionMethod = newValue;
                  });
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor, selecione o método de completude';
                  }
                  return null;
                },
              ),
              // Campo condicional para quantidade/minutos alvo, aparece se o método de completude for quantidade ou minutos
              if (_selectedCompletionMethod == 'quantity' ||
                  _selectedCompletionMethod == 'minutes')
                TextFormField(
                  controller: _targetQuantityController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText:
                        _selectedCompletionMethod == 'quantity'
                            ? 'Quantidade Alvo (ex: 1x, 2x)'
                            : 'Minutos Alvo (ex: 200min)',
                  ),
                  validator: (value) {
                    if ((_selectedCompletionMethod == 'quantity' ||
                            _selectedCompletionMethod == 'minutes') &&
                        (value == null || value.isEmpty)) {
                      return 'Este campo é obrigatório para este método de completude';
                    }
                    if (value != null &&
                        value.isNotEmpty &&
                        int.tryParse(value) == null) {
                      return 'Por favor, insira um número válido';
                    }
                    return null;
                  },
                ),
              const SizedBox(height: 20), // Espaçamento
              // Botão para adicionar o hábito
              ElevatedButton(
                onPressed:
                    _submitHabit, // Chama a função _submitHabit ao ser pressionado
                child: const Text('Adicionar Hábito'),
              ),
            ],
          ),
        ),
      ),
      // ADICIONE ESTE FLOATING ACTION BUTTON AQUI ABAIXO DO 'body:'
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const HabitListScreen()),
          );
        },
        tooltip: 'Ver Hábitos',
        child: const Icon(Icons.list),
      ),
    );
  }
}

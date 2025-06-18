import 'package:flutter/material.dart';

class SelectionScreen extends StatelessWidget {
  final String title; // Título da tela de seleção
  final Map<String, String>
  options; // Opções no formato {'valor_real': 'Nome Bonito'}
  final String? initialValue; // Valor pré-selecionado

  const SelectionScreen({
    super.key,
    required this.title,
    required this.options,
    this.initialValue,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.builder(
        itemCount: options.length,
        itemBuilder: (context, index) {
          String value = options.keys.elementAt(index);
          String displayName = options.values.elementAt(index);
          return ListTile(
            title: Text(displayName),
            trailing:
                initialValue ==
                        value // Marca a opção pré-selecionada
                    ? const Icon(Icons.check, color: Colors.blue)
                    : null,
            onTap: () {
              Navigator.pop(context, value); // Retorna o valor selecionado
            },
          );
        },
      ),
    );
  }
}

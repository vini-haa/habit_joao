import os
import traceback
import datetime # Adicione esta linha!
from flask import Flask, request, jsonify
from flask_mysqldb import MySQL

app = Flask(__name__)

# Configurações do Banco de Dados
app.config['MYSQL_HOST'] = os.environ.get('MYSQL_HOST', 'localhost')
app.config['MYSQL_USER'] = os.environ.get('MYSQL_USER', 'root')
app.config['MYSQL_PASSWORD'] = os.environ.get('MYSQL_PASSWORD', 'admin') # Mude para sua senha
app.config['MYSQL_DB'] = os.environ.get('MYSQL_DB', 'habit_tracker')

mysql = MySQL(app)

@app.route('/habits', methods=['POST'])
def add_habit():
    try:
        data = request.json
        name = data['name']
        count_method = data['count_method']
        completion_method = data['completion_method']
        description = data.get('description')
        target_quantity = data.get('target_quantity')
        target_days_per_week = data.get('target_days_per_week')

        # Validações básicas (pode ser mais robusto)
        if count_method not in ['daily', 'weekly', 'monthly']:
            return jsonify({'error': 'Invalid count_method. Must be daily, weekly, or monthly.'}), 400
        if completion_method not in ['quantity', 'minutes']:
            return jsonify({'error': 'Invalid completion_method. Must be quantity or minutes.'}), 400

        if (completion_method == 'quantity' or completion_method == 'minutes') and target_quantity is None:
            return jsonify({'error': 'target_quantity is required for quantity or minutes completion methods.'}), 400

        if count_method in ['weekly', 'monthly'] and target_days_per_week is None:
            return jsonify({'error': 'target_days_per_week is required for weekly or monthly habits.'}), 400

        cursor = mysql.connection.cursor()
        cursor.execute(
            "INSERT INTO habits (name, description, count_method, completion_method, target_quantity, target_days_per_week) VALUES (%s, %s, %s, %s, %s, %s)",
            (name, description, count_method, completion_method, target_quantity, target_days_per_week)
        )
        mysql.connection.commit()
        
        habit_id = cursor.lastrowid
        cursor.close()
        
        return jsonify({'message': 'Habit added successfully!', 'id': habit_id}), 201
    except KeyError as e:
        return jsonify({'error': f'Missing data: {e}'}), 400
    except Exception as e:
        print(f"Erro no POST /habits: {e}")
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500

@app.route('/habits', methods=['GET'])
def get_habits():
    try:
        cursor = mysql.connection.cursor()

        today = datetime.date.today()
        # Calcula o início da semana (segunda-feira) e do mês
        # Para a semana, pode variar. Aqui, pegamos o dia atual - (dia da semana - 0) para segunda-feira
        # ou - (dia da semana) para domingo. Vamos usar uma lógica simples para o dia 0 da semana.
        # Python's weekday() is 0 (Monday) to 6 (Sunday)
        start_of_week = today - datetime.timedelta(days=today.weekday()) # Segunda-feira
        start_of_month = today.replace(day=1)

        query = """
        SELECT
            h.id,
            h.name,
            h.description,
            h.count_method,
            h.completion_method,
            h.target_quantity,
            h.target_days_per_week,
            h.created_at,
            -- É completado hoje?
            (SELECT COUNT(*) FROM habit_records hr_today WHERE hr_today.habit_id = h.id AND hr_today.record_date = %s) > 0 AS is_completed_today,
            -- Última data de completude
            (SELECT MAX(hr_last.record_date) FROM habit_records hr_last WHERE hr_last.habit_id = h.id) AS last_completed_date,
            -- Progresso de quantidade/minutos na semana/mês atual
            COALESCE((SELECT SUM(hr_qty.quantity_completed) FROM habit_records hr_qty WHERE hr_qty.habit_id = h.id AND hr_qty.record_date >= %s AND hr_qty.record_date <= %s), 0) AS current_period_quantity,
            -- Dias completos na semana/mês atual
            COALESCE((SELECT COUNT(DISTINCT hr_days.record_date) FROM habit_records hr_days WHERE hr_days.habit_id = h.id AND hr_days.record_date >= %s AND hr_days.record_date <= %s), 0) AS current_period_days_completed
        FROM
            habits h
        """

        # Parametros para a query: today_str, start_of_week, today, start_of_month, today
        # A mesma data pode ser usada para múltiplos parâmetros se a query assim exigir.
        cursor.execute(query, (
            today.isoformat(), # %s para is_completed_today
            start_of_week.isoformat(), today.isoformat(), # %s para current_period_quantity (semana)
            start_of_week.isoformat(), today.isoformat(), # %s para current_period_days_completed (semana)
        ))

        # Isso é um pouco simplificado. Para hábitos mensais, o range deveria ser start_of_month até today.
        # O ideal seria fazer isso no Python de forma mais dinâmica, ou ter queries separadas.
        # Por enquanto, vamos usar o range da semana para ambos para testar a estrutura.

        habits = cursor.fetchall()

        habits_list = []
        if cursor.description:
            column_names = [desc[0] for desc in cursor.description]
            for habit_tuple in habits:
                habit_dict = dict(zip(column_names, habit_tuple))

                # Converte 0/1 do MySQL para True/False em Python
                habit_dict['is_completed_today'] = bool(habit_dict['is_completed_today'])

                # Converte datetime.date para string para JSON, se necessário
                if 'last_completed_date' in habit_dict and isinstance(habit_dict['last_completed_date'], datetime.date):
                    habit_dict['last_completed_date'] = habit_dict['last_completed_date'].isoformat()

                habits_list.append(habit_dict)

        cursor.close()

        return jsonify(habits_list), 200
    except Exception as e:
        print(f"Erro ao obter hábitos: {e}")
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500

@app.route('/habit_records', methods=['POST'])
def add_habit_record():
    try:
        data = request.json
        habit_id = data['habit_id']
        record_date_str = data['record_date'] # Ex: 'YYYY-MM-DD'
        quantity_completed = data.get('quantity_completed') # Pode ser nulo se o método não for de quantidade/minutos

        # Validação básica
        if not habit_id or not record_date_str:
            return jsonify({'error': 'habit_id and record_date are required.'}), 400

        # Opcional: Validar se habit_id existe na tabela habits
        cursor = mysql.connection.cursor()
        cursor.execute("SELECT id FROM habits WHERE id = %s", (habit_id,))
        if not cursor.fetchone():
            cursor.close()
            return jsonify({'error': f'Habit with ID {habit_id} not found.'}), 404

        # Tenta inserir o registro de completude
        # A restrição UNIQUE (habit_id, record_date) no MySQL vai evitar duplicatas no mesmo dia.
        # Se a inserção falhar por duplicidade, o DBAPIError será capturado.
        cursor.execute(
            "INSERT INTO habit_records (habit_id, record_date, quantity_completed) VALUES (%s, %s, %s)",
            (habit_id, record_date_str, quantity_completed)
        )
        mysql.connection.commit()

        record_id = cursor.lastrowid
        cursor.close()

        return jsonify({'message': 'Habit record added successfully!', 'id': record_id}), 201
    except Exception as e:
        # Imprime o traceback para depuração
        print(f"Erro ao adicionar registro de hábito: {e}")
        traceback.print_exc()

        # Se for um erro de duplicidade (UNIQUE constraint), retorne um 409 Conflict
        if "Duplicate entry" in str(e) and "for key 'habit_id'" in str(e):
            return jsonify({'error': 'Registro para este hábito e data já existe.'}), 409

        return jsonify({'error': str(e)}), 500


if __name__ == '__main__':
    app.run(debug=True)
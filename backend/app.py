import datetime
import os
import traceback
import json # Adicionar para lidar com reminder_days

from flask import Flask, jsonify, request
from flask_mysqldb import MySQL

app = Flask(__name__)

# Configurações do Banco de Dados
app.config["MYSQL_HOST"] = os.environ.get("MYSQL_HOST", "localhost")
app.config["MYSQL_USER"] = os.environ.get("MYSQL_USER", "root")
app.config["MYSQL_PASSWORD"] = os.environ.get("MYSQL_PASSWORD", "admin")
app.config["MYSQL_DB"] = os.environ.get("MYSQL_DB", "habit_tracker")
app.config["MYSQL_CURSORCLASS"] = "DictCursor"

mysql = MySQL(app)


def calculate_streak(completed_dates_raw):
    if not completed_dates_raw:
        return 0
    completed_dates = sorted(
        [
            d if isinstance(d, datetime.date) else datetime.date.fromisoformat(str(d))
            for d in completed_dates_raw
        ],
        reverse=True,
    )
    current_streak = 0
    today = datetime.date.today()
    yesterday = today - datetime.timedelta(days=1)

    if not completed_dates:
        return 0

    if completed_dates[0] == today:
        current_streak = 1
        compare_date = yesterday
    elif completed_dates[0] == yesterday:
        current_streak = 1
        compare_date = yesterday - datetime.timedelta(days=1)
    else:
        return 0

    for i in range(1, len(completed_dates)):
        if completed_dates[i] == compare_date:
            current_streak += 1
            compare_date -= datetime.timedelta(days=1)
        elif completed_dates[i] < compare_date:
            break
    return current_streak


@app.route("/categories", methods=["GET"])
def get_all_categories():
    try:
        cursor = mysql.connection.cursor()
        cursor.execute("SELECT id, name FROM categories ORDER BY name ASC")
        categories = cursor.fetchall()
        cursor.close()
        return jsonify(categories), 200
    except Exception as e:
        traceback.print_exc()
        return jsonify(
            {"error": "Erro interno ao buscar categorias", "details": str(e)}
        ), 500


@app.route("/habits", methods=["POST"])
def add_habit():
    try:
        data = request.json
        name = data["name"]
        count_method = data["count_method"]
        completion_method = data["completion_method"]
        description = data.get("description")
        target_quantity = data.get("target_quantity")
        target_days_per_week = data.get("target_days_per_week")
        category_ids = data.get("category_ids", [])

        # Novos campos para lembretes
        reminder_time_str = data.get("reminder_time") # Espera HH:MM
        reminder_days_list = data.get("reminder_days") # Espera uma lista de strings, ex: ["MON", "TUE"]
        reminder_enabled = data.get("reminder_enabled", False)

        reminder_time = None
        if reminder_time_str:
            try:
                reminder_time = datetime.datetime.strptime(reminder_time_str, "%H:%M").time()
            except ValueError:
                return jsonify({"error": "Formato de reminder_time inválido. Use HH:MM."}), 400

        reminder_days_db = None
        if reminder_days_list and isinstance(reminder_days_list, list):
            reminder_days_db = ",".join(reminder_days_list) # Armazena como string separada por vírgula

        if not name:
            return jsonify({"error": "Name is required"}), 400

        cursor = mysql.connection.cursor()
        cursor.execute(
            """INSERT INTO habits (name, description, count_method, completion_method,
                                 target_quantity, target_days_per_week,
                                 reminder_time, reminder_days, reminder_enabled)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)""",
            (
                name,
                description,
                count_method,
                completion_method,
                target_quantity,
                target_days_per_week,
                reminder_time,
                reminder_days_db,
                reminder_enabled,
            ),
        )
        habit_id = cursor.lastrowid

        if isinstance(category_ids, list):
            for category_id in category_ids:
                cursor.execute(
                    "INSERT INTO habit_categories (habit_id, category_id) VALUES (%s, %s)",
                    (habit_id, category_id),
                )
        mysql.connection.commit()
        cursor.close()
        return jsonify({"message": "Habit added successfully!", "id": habit_id}), 201
    except KeyError as e:
        traceback.print_exc()
        return jsonify({"error": f"Missing data: {e}"}), 400
    except Exception as e:
        traceback.print_exc()
        mysql.connection.rollback()
        return jsonify({"error": str(e)}), 500


@app.route("/habits", methods=["GET"])
def get_habits():
    try:
        cursor = mysql.connection.cursor()
        today = datetime.date.today()
        start_of_current_period = today - datetime.timedelta(days=today.weekday())

        base_query = """
            SELECT
                h.id, h.name, h.description, h.count_method, h.completion_method,
                h.target_quantity, h.target_days_per_week, h.created_at,
                h.reminder_time, h.reminder_days, h.reminder_enabled,
                (SELECT COUNT(*) FROM habit_records hr_today WHERE hr_today.habit_id = h.id AND hr_today.record_date = %s) > 0 AS is_completed_today,
                (SELECT MAX(hr_last.record_date) FROM habit_records hr_last WHERE hr_last.habit_id = h.id) AS last_completed_date,
                COALESCE((
                    SELECT SUM(hr_qty.quantity_completed)
                    FROM habit_records hr_qty
                    WHERE hr_qty.habit_id = h.id
                      AND hr_qty.record_date >= %s
                      AND hr_qty.record_date <= %s
                ), 0) AS current_period_quantity,
                COALESCE((
                    SELECT COUNT(DISTINCT hr_days.record_date)
                    FROM habit_records hr_days
                    WHERE hr_days.habit_id = h.id
                      AND hr_days.record_date >= %s
                      AND hr_days.record_date <= %s
                ), 0) AS current_period_days_completed
            FROM habits h
        """

        query_params_dates = [
            today.isoformat(),
            start_of_current_period.isoformat(),
            today.isoformat(),
            start_of_current_period.isoformat(),
            today.isoformat(),
        ]

        filter_category_id = request.args.get("category_id", type=int)
        final_query_params = list(query_params_dates)

        if filter_category_id:
            base_query += """
                JOIN habit_categories hc ON h.id = hc.habit_id
                WHERE hc.category_id = %s
            """
            final_query_params.append(filter_category_id)

        base_query += " ORDER BY h.created_at DESC"

        cursor.execute(base_query, tuple(final_query_params))
        habits_results = cursor.fetchall()

        for habit in habits_results:
            cat_cursor = mysql.connection.cursor()
            cat_cursor.execute(
                """
                SELECT c.id, c.name FROM categories c
                JOIN habit_categories hc ON c.id = hc.category_id
                WHERE hc.habit_id = %s
            """,
                (habit["id"],),
            )
            habit["categories"] = cat_cursor.fetchall()
            cat_cursor.close()

            streak_cursor = mysql.connection.cursor()
            if habit["completion_method"] == "boolean":
                streak_cursor.execute(
                    "SELECT DISTINCT record_date FROM habit_records WHERE habit_id = %s ORDER BY record_date DESC",
                    (habit["id"],),
                )
            elif (
                habit["completion_method"] in ["quantity", "minutes"]
                and habit["target_quantity"] is not None
                and habit["target_quantity"] > 0
            ):
                streak_cursor.execute(
                    """
                    SELECT record_date
                    FROM (
                        SELECT record_date, SUM(quantity_completed) as total_quantity_today
                        FROM habit_records
                        WHERE habit_id = %s
                        GROUP BY record_date
                    ) AS daily_totals
                    WHERE daily_totals.total_quantity_today >= %s
                    ORDER BY record_date DESC
                    """,
                    (habit["id"], habit["target_quantity"]),
                )
            else: # Caso de quantity/minutes sem meta, contamos qualquer registro como parte da streak
                streak_cursor.execute(
                    "SELECT DISTINCT record_date FROM habit_records WHERE habit_id = %s ORDER BY record_date DESC",
                    (habit["id"],),
                )


            completed_dates_raw_dicts = streak_cursor.fetchall()
            completed_dates_raw = [
                row["record_date"] for row in completed_dates_raw_dicts
            ]
            streak_cursor.close()
            habit["current_streak"] = calculate_streak(completed_dates_raw)

            habit["is_completed_today"] = bool(habit["is_completed_today"])
            if isinstance(habit.get("last_completed_date"), datetime.date):
                habit["last_completed_date"] = habit["last_completed_date"].isoformat()
            if isinstance(habit.get("created_at"), datetime.datetime):
                habit["created_at"] = habit["created_at"].isoformat()

            # Formatar reminder_time e reminder_days para o frontend
            if isinstance(habit.get("reminder_time"), datetime.timedelta): # MySQL TIME é retornado como timedelta
                total_seconds = int(habit["reminder_time"].total_seconds())
                hours = total_seconds // 3600
                minutes = (total_seconds % 3600) // 60
                habit["reminder_time"] = f"{hours:02d}:{minutes:02d}"
            elif habit.get("reminder_time") is not None: # Caso já seja string ou outro formato, tentar manter
                 habit["reminder_time"] = str(habit["reminder_time"])


            if habit.get("reminder_days") and isinstance(habit["reminder_days"], str):
                habit["reminder_days"] = habit["reminder_days"].split(',')
            elif not habit.get("reminder_days"):
                 habit["reminder_days"] = []


            habit["reminder_enabled"] = bool(habit.get("reminder_enabled", False))


        cursor.close()
        return jsonify(habits_results), 200
    except Exception as e:
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@app.route("/habits/<int:habit_id>", methods=["PUT"])
def update_habit(habit_id):
    try:
        data = request.json
        cursor = mysql.connection.cursor()
        cursor.execute("SELECT id FROM habits WHERE id = %s", (habit_id,))
        if not cursor.fetchone():
            cursor.close()
            return jsonify({"error": f"Habit with ID {habit_id} not found."}), 404

        update_fields_habits = []
        params_habits = []
        allowed_fields = [
            "name",
            "description",
            "count_method",
            "completion_method",
            "target_quantity",
            "target_days_per_week",
            "reminder_enabled"
        ]
        for field in allowed_fields:
            if field in data:
                update_fields_habits.append(f"{field} = %s")
                params_habits.append(data[field])

        if "reminder_time" in data:
            reminder_time_str = data.get("reminder_time")
            if reminder_time_str:
                try:
                    reminder_time = datetime.datetime.strptime(reminder_time_str, "%H:%M").time()
                    update_fields_habits.append("reminder_time = %s")
                    params_habits.append(reminder_time)
                except ValueError:
                     # Mantém o valor existente ou define como NULL se string vazia
                    if reminder_time_str == "":
                        update_fields_habits.append("reminder_time = NULL")
                    # Não adiciona aos params_habits se o formato for inválido e não for string vazia
                    # Opcionalmente, pode-se retornar um erro aqui.
            elif reminder_time_str is None: # Permitir definir como NULL
                update_fields_habits.append("reminder_time = NULL")


        if "reminder_days" in data:
            reminder_days_list = data.get("reminder_days")
            if reminder_days_list and isinstance(reminder_days_list, list):
                reminder_days_db = ",".join(reminder_days_list)
                update_fields_habits.append("reminder_days = %s")
                params_habits.append(reminder_days_db)
            elif not reminder_days_list: # Lista vazia ou None
                update_fields_habits.append("reminder_days = NULL")


        if update_fields_habits:
            query_habits = (
                "UPDATE habits SET "
                + ", ".join(update_fields_habits)
                + " WHERE id = %s"
            )
            params_habits.append(habit_id)
            cursor.execute(query_habits, tuple(params_habits))

        if "category_ids" in data:
            new_category_ids = data.get("category_ids", [])
            cursor.execute(
                "DELETE FROM habit_categories WHERE habit_id = %s", (habit_id,)
            )
            if isinstance(new_category_ids, list):
                for category_id in new_category_ids:
                    cursor.execute(
                        "INSERT INTO habit_categories (habit_id, category_id) VALUES (%s, %s)",
                        (habit_id, category_id),
                    )
        mysql.connection.commit()
        cursor.close()
        return jsonify(
            {"message": f"Habit with ID {habit_id} updated successfully!"}
        ), 200
    except Exception as e:
        traceback.print_exc()
        mysql.connection.rollback()
        return jsonify({"error": str(e)}), 500

# ... (o restante das rotas /habits/<id> DELETE, /habit_records POST, /habit_records/today DELETE, /habits/<id>/records GET, /all_habit_records GET permanecem iguais)

@app.route("/habits/<int:habit_id>", methods=["DELETE"])
def delete_habit(habit_id):
    try:
        cursor = mysql.connection.cursor()
        # Primeiro deletar de tabelas dependentes
        cursor.execute("DELETE FROM habit_records WHERE habit_id = %s", (habit_id,))
        cursor.execute("DELETE FROM habit_categories WHERE habit_id = %s", (habit_id,))
        # Depois deletar o hábito principal
        cursor.execute("DELETE FROM habits WHERE id = %s", (habit_id,))
        mysql.connection.commit()

        if cursor.rowcount == 0: # Verifica se o hábito foi deletado da tabela 'habits'
            cursor.close()
            # Mesmo que não encontre em 'habits', as deleções em cascata podem ter ocorrido ou não.
            # Para consistência, podemos considerar que se não estava em 'habits', já foi "deletado".
            return jsonify({"message": f"Habit with ID {habit_id} not found or already deleted."}), 200
            # Alternativamente, se quiser ser estrito sobre a existência prévia:
            # return jsonify({"error": f"Habit with ID {habit_id} not found."}), 404

        cursor.close()
        return jsonify(
            {"message": f"Habit with ID {habit_id} and its related records deleted successfully!"}
        ), 200
    except Exception as e:
        traceback.print_exc()
        mysql.connection.rollback()
        return jsonify({"error": str(e)}), 500


@app.route("/habit_records", methods=["POST"])
def add_habit_record():
    try:
        data = request.json
        habit_id = data["habit_id"]
        record_date_str = data["record_date"]
        quantity_to_add = data.get("quantity_completed", 1) # Default para 1 se não fornecido

        if not habit_id or not record_date_str:
            return jsonify({"error": "habit_id and record_date are required."}), 400

        # Valida o formato da data
        try:
            datetime.date.fromisoformat(record_date_str)
        except ValueError:
            return jsonify({"error": "Invalid record_date format. Use YYYY-MM-DD."}), 400


        cursor = mysql.connection.cursor()
        cursor.execute(
            "SELECT id, completion_method FROM habits WHERE id = %s", (habit_id,)
        )
        habit_info = cursor.fetchone()
        if not habit_info:
            cursor.close()
            return jsonify({"error": f"Habit with ID {habit_id} not found."}), 404

        if habit_info["completion_method"] == "boolean":
            # Para booleano, se já existe um registro, não faz nada ou atualiza timestamp.
            # Se não existe, insere com quantity_completed = 1.
            # A lógica ON DUPLICATE KEY UPDATE já lida com isso se a chave for (habit_id, record_date)
            final_quantity = 1 # Para booleanos, a quantidade é sempre 1 ao marcar.
            sql = """
                INSERT INTO habit_records (habit_id, record_date, quantity_completed)
                VALUES (%s, %s, %s)
                ON DUPLICATE KEY UPDATE quantity_completed = VALUES(quantity_completed),
                                       created_at = CURRENT_TIMESTAMP
            """
            params = (habit_id, record_date_str, final_quantity)

        else: # quantity ou minutes
            if not isinstance(quantity_to_add, int) or quantity_to_add <= 0:
                return jsonify({"error": "quantity_completed must be a positive integer for this habit type."}), 400

            sql = """
                INSERT INTO habit_records (habit_id, record_date, quantity_completed)
                VALUES (%s, %s, %s)
                ON DUPLICATE KEY UPDATE quantity_completed = quantity_completed + VALUES(quantity_completed),
                                       created_at = CURRENT_TIMESTAMP
            """
            params = (habit_id, record_date_str, quantity_to_add)


        cursor.execute(sql, params)
        mysql.connection.commit()
        record_id = cursor.lastrowid if cursor.lastrowid else True # Se for update, lastrowid pode ser 0
        cursor.close()
        return jsonify(
            {"message": "Habit record added/updated successfully!", "id": record_id}
        ), 201
    except Exception as e:
        traceback.print_exc()
        mysql.connection.rollback()
        return jsonify({"error": str(e)}), 500


@app.route("/habit_records/today", methods=["DELETE"])
def delete_habit_record_today():
    habit_id = request.args.get("habit_id", type=int)
    record_date_str = datetime.date.today().isoformat()
    if not habit_id:
        return jsonify({"error": "habit_id is required as a query parameter."}), 400
    try:
        cursor = mysql.connection.cursor()
        cursor.execute("SELECT id FROM habits WHERE id = %s", (habit_id,))
        if not cursor.fetchone():
            cursor.close()
            return jsonify({"error": f"Habit with ID {habit_id} not found."}), 404
        result = cursor.execute(
            "DELETE FROM habit_records WHERE habit_id = %s AND record_date = %s",
            (habit_id, record_date_str),
        )
        mysql.connection.commit()
        cursor.close()
        if result > 0:
            return jsonify(
                {
                    "message": f"Habit record for habit {habit_id} on {record_date_str} deleted successfully."
                }
            ), 200
        else:
            return jsonify(
                {
                    "message": f"No habit record found for habit {habit_id} on {record_date_str} to delete."
                }
            ), 200 # Retorna 200 mesmo se nada foi deletado, pois a "condição" (não ter registro) foi atingida.
    except Exception as e:
        traceback.print_exc()
        mysql.connection.rollback()
        return jsonify(
            {"error": "Failed to delete habit record for today.", "details": str(e)}
        ), 500


@app.route("/habits/<int:habit_id>/records", methods=["GET"])
def get_habit_records_for_heatmap(habit_id):
    try:
        start_date_str = request.args.get("start_date")
        end_date_str = request.args.get("end_date")
        cursor = mysql.connection.cursor()
        query = "SELECT record_date, quantity_completed FROM habit_records WHERE habit_id = %s"
        params = [habit_id]
        if start_date_str:
            query += " AND record_date >= %s"
            params.append(start_date_str)
        if end_date_str:
            query += " AND record_date <= %s"
            params.append(end_date_str)
        query += " ORDER BY record_date ASC"
        cursor.execute(query, tuple(params))
        records = cursor.fetchall()
        cursor.close()
        formatted_records = [
            {
                "record_date": record["record_date"].isoformat(),
                "quantity_completed": record["quantity_completed"],
            }
            for record in records
        ]
        return jsonify(formatted_records), 200
    except Exception as e:
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@app.route("/all_habit_records", methods=["GET"])
def get_all_habit_records_for_heatmap():
    try:
        start_date_str = request.args.get("start_date")
        end_date_str = request.args.get("end_date")
        cursor = mysql.connection.cursor()
        query = "SELECT habit_id, record_date, quantity_completed FROM habit_records"
        params = []
        where_clauses = []
        if start_date_str:
            where_clauses.append("record_date >= %s")
            params.append(start_date_str)
        if end_date_str:
            where_clauses.append("record_date <= %s")
            params.append(end_date_str)
        if where_clauses:
            query += " WHERE " + " AND ".join(where_clauses)
        query += " ORDER BY record_date ASC"
        cursor.execute(query, tuple(params))
        records = cursor.fetchall()
        cursor.close()
        formatted_records = [
            {
                "habit_id": record["habit_id"],
                "record_date": record["record_date"].isoformat(),
                "quantity_completed": record["quantity_completed"],
            }
            for record in records
        ]
        return jsonify(formatted_records), 200
    except Exception as e:
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@app.route("/export_data", methods=["GET"])
def export_data():
    try:
        cursor = mysql.connection.cursor()
        categories_raw = cursor.execute("SELECT id, name FROM categories").fetchall()
        categories_export = [{"id_json": cat["id"], "name": cat["name"]} for cat in categories_raw]

        cursor.execute("""
            SELECT h.id, h.name, h.description, h.count_method, h.completion_method,
                   h.target_quantity, h.target_days_per_week, h.created_at,
                   h.reminder_time, h.reminder_days, h.reminder_enabled
            FROM habits h
        """)
        habits_raw = cursor.fetchall()
        habits_export = []
        for habit_raw in habits_raw:
            cursor.execute("SELECT category_id FROM habit_categories WHERE habit_id = %s", (habit_raw["id"],))
            habit_categories_raw = cursor.fetchall()
            category_ids_json = [hc["category_id"] for hc in habit_categories_raw]

            reminder_time_exp = None
            if isinstance(habit_raw.get("reminder_time"), datetime.timedelta):
                total_seconds = int(habit_raw["reminder_time"].total_seconds())
                hours = total_seconds // 3600
                minutes = (total_seconds % 3600) // 60
                reminder_time_exp = f"{hours:02d}:{minutes:02d}"
            elif habit_raw.get("reminder_time") is not None:
                 reminder_time_exp = str(habit_raw.get("reminder_time"))


            reminder_days_exp = []
            if habit_raw.get("reminder_days") and isinstance(habit_raw["reminder_days"], str):
                reminder_days_exp = habit_raw["reminder_days"].split(',')

            habits_export.append({
                "id_json": habit_raw["id"], "name": habit_raw["name"], "description": habit_raw["description"],
                "count_method": habit_raw["count_method"], "completion_method": habit_raw["completion_method"],
                "target_quantity": habit_raw["target_quantity"], "target_days_per_week": habit_raw["target_days_per_week"],
                "created_at": habit_raw["created_at"].isoformat() if isinstance(habit_raw["created_at"], (datetime.datetime, datetime.date)) else str(habit_raw["created_at"]),
                "category_ids_json": category_ids_json,
                "reminder_time": reminder_time_exp,
                "reminder_days": reminder_days_exp,
                "reminder_enabled": bool(habit_raw.get("reminder_enabled", False))
            })

        cursor.execute("SELECT habit_id, record_date, quantity_completed FROM habit_records")
        records_raw = cursor.fetchall()
        records_export = [{
            "habit_id_json": rec["habit_id"],
            "record_date": rec["record_date"].isoformat() if isinstance(rec["record_date"], datetime.date) else str(rec["record_date"]),
            "quantity_completed": rec["quantity_completed"]
        } for rec in records_raw]
        cursor.close()
        return jsonify({"categories": categories_export, "habits": habits_export, "habit_records": records_export}), 200
    except Exception as e:
        traceback.print_exc()
        return jsonify({"error": "Erro ao exportar dados", "details": str(e)}), 500

@app.route("/import_data", methods=["POST"])
def import_data():
    try:
        data = request.json
        imported_categories = data.get("categories", [])
        imported_habits = data.get("habits", [])
        imported_records = data.get("habit_records", [])

        cursor = mysql.connection.cursor()
        cursor.execute("SET FOREIGN_KEY_CHECKS=0")
        cursor.execute("DELETE FROM habit_records")
        cursor.execute("DELETE FROM habit_categories")
        cursor.execute("DELETE FROM habits")
        cursor.execute("DELETE FROM categories")
        cursor.execute("SET FOREIGN_KEY_CHECKS=1")

        category_id_map = {}
        for cat_data in imported_categories:
            cursor.execute("INSERT INTO categories (name) VALUES (%s)", (cat_data["name"],))
            new_category_id = cursor.lastrowid
            category_id_map[cat_data["id_json"]] = new_category_id

        habit_id_map = {}
        for habit_data in imported_habits:
            created_at_dt = None
            if habit_data.get("created_at"):
                try: created_at_dt = datetime.datetime.fromisoformat(habit_data["created_at"].replace("Z", "+00:00"))
                except ValueError:
                    try: created_at_dt = datetime.datetime.combine(datetime.date.fromisoformat(habit_data["created_at"]), datetime.time.min)
                    except ValueError: pass

            reminder_time_db = None
            if habit_data.get("reminder_time"):
                try: reminder_time_db = datetime.datetime.strptime(habit_data["reminder_time"], "%H:%M").time()
                except: pass # Ignora se o formato for inválido

            reminder_days_db_val = None
            if habit_data.get("reminder_days") and isinstance(habit_data["reminder_days"], list):
                reminder_days_db_val = ",".join(habit_data["reminder_days"])

            cursor.execute(
                """INSERT INTO habits (name, description, count_method, completion_method,
                                     target_quantity, target_days_per_week, created_at,
                                     reminder_time, reminder_days, reminder_enabled)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
                (habit_data["name"], habit_data.get("description"), habit_data["count_method"], habit_data["completion_method"],
                 habit_data.get("target_quantity"), habit_data.get("target_days_per_week"), created_at_dt,
                 reminder_time_db, reminder_days_db_val, habit_data.get("reminder_enabled", False))
            )
            new_habit_id = cursor.lastrowid
            habit_id_map[habit_data["id_json"]] = new_habit_id

            for json_category_id in habit_data.get("category_ids_json", []):
                if json_category_id in category_id_map:
                    cursor.execute("INSERT INTO habit_categories (habit_id, category_id) VALUES (%s, %s)",
                                   (new_habit_id, category_id_map[json_category_id]))

        for record_data in imported_records:
            json_habit_id = record_data["habit_id_json"]
            if json_habit_id in habit_id_map:
                record_date_dt = None
                if record_data.get("record_date"):
                    try: record_date_dt = datetime.date.fromisoformat(record_data["record_date"])
                    except ValueError: pass
                if record_date_dt:
                    cursor.execute(
                        "INSERT INTO habit_records (habit_id, record_date, quantity_completed) VALUES (%s, %s, %s)",
                        (habit_id_map[json_habit_id], record_date_dt, record_data.get("quantity_completed", 1)))
        mysql.connection.commit()
        cursor.close()
        return jsonify({"message": "Dados importados com sucesso!"}), 201
    except KeyError as e:
        traceback.print_exc(); mysql.connection.rollback()
        return jsonify({"error": f"Formato JSON inválido. Campo faltando: {e}"}), 400
    except Exception as e:
        traceback.print_exc(); mysql.connection.rollback()
        return jsonify({"error": "Erro ao importar dados", "details": str(e)}), 500

@app.route("/delete_all_data", methods=["DELETE"])
def delete_all_data():
    try:
        cursor = mysql.connection.cursor()
        cursor.execute("SET FOREIGN_KEY_CHECKS=0")
        cursor.execute("DELETE FROM habit_records")
        cursor.execute("DELETE FROM habit_categories")
        cursor.execute("DELETE FROM habits")
        cursor.execute("DELETE FROM categories")
        cursor.execute("SET FOREIGN_KEY_CHECKS=1")
        mysql.connection.commit()
        cursor.close()
        return jsonify({"message": "Todos os dados foram deletados com sucesso!"}), 200
    except Exception as e:
        traceback.print_exc()
        mysql.connection.rollback()
        return jsonify({"error": "Erro ao deletar todos os dados", "details": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
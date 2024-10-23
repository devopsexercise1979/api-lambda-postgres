import json
import os
import psycopg2

DB_HOST = os.getenv('DB_HOST')
DB_NAME = os.getenv('DB_NAME')
DB_USER = os.getenv('DB_USER')
DB_PASSWORD = os.getenv('DB_PASSWORD')

def get_connection():
    return psycopg2.connect(
        host=DB_HOST,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD
    )

def lambda_handler(event, context):
    try:
        conn = get_connection()
        cursor = conn.cursor()

        # Determine the HTTP method used
        if event['httpMethod'] == 'POST':
            body = json.loads(event['body'])  # Parse the JSON payload
            name = body.get('name')
            age = body.get('age')

            # Ensure both name and age are provided
            if not name or not age:
                return {"statusCode": 400, "body": json.dumps({"error": "Name and age are required"})}

            cursor.execute("INSERT INTO users (name, age) VALUES (%s, %s)", (name, age))
            conn.commit()
            return {"statusCode": 201, "body": json.dumps({"message": "User added successfully"})}

        elif event['httpMethod'] == 'GET':
            cursor.execute("SELECT name, age FROM users")
            users = cursor.fetchall()

            # Transform the result into a list of dictionaries
            users_list = [{"name": name, "age": age} for name, age in users]
            return {"statusCode": 200, "body": json.dumps(users_list)}

        else:
            # Return 405 if the method is not GET or POST
            return {"statusCode": 405, "body": json.dumps({"error": "Method not allowed"})}

    except Exception as e:
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}

    finally:
        cursor.close()
        conn.close()

package com.example.a;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.Statement;

public class CriticalSQLInjection {

    public void vulnerableSql(String userInput) {
        try {
            Connection conn = DriverManager.getConnection("jdbc:mysql://localhost/test", "root", "password");
            Statement stmt = conn.createStatement();

            // CRITICAL: SQL Injection vulnerability
            String sql = "SELECT * FROM users WHERE username = '" + userInput + "'";
            stmt.executeQuery(sql);

            conn.close();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
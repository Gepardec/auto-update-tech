package com.example.a;

import java.io.BufferedReader;
import java.io.InputStreamReader;

public class RiskyCode {
    public static String PASSWORD = "hardcoded123"; // Security issue
    public static String PASSWORD_NEW = "hardcoded123"; // Security issue

    public void doSomething() {
        if (true) { // Code smell
            System.out.println("Always true condition");
        }
    }

    public void runCommand(String userInput) throws Exception {
        // CRITICAL: Command Injection vulnerability
        Process p = Runtime.getRuntime().exec("ping " + userInput);
        BufferedReader reader = new BufferedReader(new InputStreamReader(p.getInputStream()));
        String line;
        while ((line = reader.readLine()) != null) {
            System.out.println(line);
        }
    }

    public static void main(String[] args) {
        int i = 5;
        System.out.printf("i=%d%n", i);
    }
}

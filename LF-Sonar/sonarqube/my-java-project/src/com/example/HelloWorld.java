package com.example;

public class App {
    public static void main(String[] args) {
        System.out.println("Hello, World!");
        new App().exampleBugs();
        new App().exampleCodeSmells();
    }

    public void exampleBugs() {
        // Bug: NullPointerException
        String value = null;
        System.out.println(value.trim()); // triggers S2259: Null pointer dereference
    }

    public void exampleCodeSmells() {
        // Code Smell: empty if block
        if (true) {
        }

        // Code Smell: empty catch block
        try {
            int a = 1 / 0;
        } catch (ArithmeticException e) {
        }
    }

    // Bug: Return null instead of empty array
    public String[] getValues() {
        return null; // triggers S1168: return empty array or collection instead of null
    }

    // Vulnerability: Hardcoded credentials (SonarWay flags hardcoded passwords if configured with secret rules)
    private String password = "SuperSecret123!";
}

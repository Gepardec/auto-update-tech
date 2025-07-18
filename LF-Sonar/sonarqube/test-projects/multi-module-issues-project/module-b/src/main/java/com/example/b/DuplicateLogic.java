package com.example.b;

public class DuplicateLogic {
    public void process() {
        try {
            int x = 1 / 0;
        } catch (Exception e) {
            // Swallowing exception
            System.out.println("Exception caught");
        }

        for (int i = 0; i < 3; i++) {
            System.out.println("Duplicate line");
        }

        for (int i = 0; i < 3; i++) {
            System.out.println("Duplicate line");
        }
    }
}

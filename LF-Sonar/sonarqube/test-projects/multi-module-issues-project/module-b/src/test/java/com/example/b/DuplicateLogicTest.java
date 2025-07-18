package com.example.b;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

public class DuplicateLogicTest {

    @Test
    public void testProcess() {
        DuplicateLogic dl = new DuplicateLogic();
        dl.process();
        assertEquals(1, 1); // Dummy test
    }
}

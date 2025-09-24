package at.gepardec.openrewrite;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;

import static org.junit.jupiter.api.Assertions.assertTrue;

public class MainTest3 {

    private final ByteArrayOutputStream outContent = new ByteArrayOutputStream();
    private final PrintStream originalOut = System.out;

    @BeforeEach
    public void setUpStreams() {
        System.setOut(new PrintStream(outContent));
    }

    @AfterEach
    public void restoreStreams() {
        System.setOut(originalOut);
    }

    @Test
    public void testMainOutputContainsHello() {
        Main3.main(new String[]{});
        String output = outContent.toString();
        assertTrue(output.contains("Hello and welcome3!"), "Output should contain greeting");
    }

    @Test
    public void testMainOutputContainsNumbers() {
        Main3.main(new String[]{});
        String output = outContent.toString();
        for (int i = 1; i <= 5; i++) {
            assertTrue(output.contains("i = " + i), "Output should contain i = " + i);
        }
    }
}

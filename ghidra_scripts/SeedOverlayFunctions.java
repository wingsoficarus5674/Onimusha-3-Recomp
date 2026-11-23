// Ghidra pre-script for overlay modules: create functions at the addresses listed in
// <seedsDir>/<module>.seeds (one hex address per line) before auto-analysis runs.
// Usage: -preScript SeedOverlayFunctions.java <seedsDir>
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import java.io.File;
import java.nio.file.Files;

public class SeedOverlayFunctions extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        String base = new File(currentProgram.getExecutablePath()).getName().replaceAll("\\.elf$", "");
        File seeds = new File(args.length > 0 ? args[0] : ".", base + ".seeds");
        if (!seeds.exists()) {
            println("no seeds: " + seeds);
            return;
        }
        int made = 0;
        for (String line : Files.readAllLines(seeds.toPath())) {
            line = line.trim();
            if (line.isEmpty()) continue;
            Address a = toAddr(Long.decode(line));
            if (getFunctionAt(a) != null) continue;
            disassemble(a);
            if (createFunction(a, null) != null) made++;
        }
        println("seeded " + made + " functions for " + base);
    }
}

# Onimusha 3 code overlays (used by 3b_recompile_overlays.bat).
#
#   overlays.ps1 -Extract  <IMAGE.AFS> <workDir> [<SLUS_206.94>]
#       Finds the Capcom "LINK" modules (*.ldt) in IMAGE.AFS, decompresses them and writes every
#       code module ("MWo3" image) as <workDir>\elf\<name>.elf (one load segment at the module's
#       link address) plus function-start hints in <workDir>\seeds\<name>.seeds for Ghidra.
#   overlays.ps1 -MainExtra <output\register_functions.cpp> <functions.csv> <SLUS_206.94> <elfDir> <outCsv>
#       Lists main-ELF addresses that overlay code jumps to but the main recompile has no entry for
#       (code only overlays call), as a ps2_recomp function CSV.
#   overlays.ps1 -Generate <recompDir> <elfDir> <destDir> [<SLUS_206.94>]
#       Turns ps2_recomp's output for each module (<recompDir>\<name>\) into sources for
#       ps2xRuntime\src\runner_overlays: namespaced function bodies plus a table that registers
#       the module with the runtime (see patches\0015-recompiled-code-overlays.patch).
#   overlays.ps1 -GhidraScript <ExportPS2Functions.java> <outFile>
#       Writes ExportPS2Overlay.java: PS2Recomp's exporter, writing <outDir>\<module>.csv/.toml
#       instead of asking for file names.
param(
    [switch]$Extract,
    [switch]$Generate,
    [switch]$MainExtra,
    [switch]$GhidraScript,
    [Parameter(Position = 0)][string]$A,
    [Parameter(Position = 1)][string]$B,
    [Parameter(Position = 2)][string]$C,
    [Parameter(Position = 3)][string]$D,
    [Parameter(Position = 4)][string]$E
)
$ErrorActionPreference = 'Stop'

$source = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

public static class O3Overlays
{
    static uint U32(byte[] d, int o) { return BitConverter.ToUInt32(d, o); }

    // Capcom CPK0: LZSS with a 4 KB window starting at 0xFEE, flag bytes, literal when the bit is set.
    static byte[] Lzss(byte[] src, int start, int end, int outSize)
    {
        byte[] win = new byte[4096];
        byte[] outBuf = new byte[outSize];
        int r = 0xFEE, n = 0, i = start;
        uint flags = 0;
        while (n < outSize && i < end)
        {
            flags >>= 1;
            if ((flags & 0x100) == 0) { flags = (uint)src[i++] | 0xFF00u; }
            if ((flags & 1) != 0)
            {
                byte c = src[i++];
                outBuf[n++] = c; win[r] = c; r = (r + 1) & 0xFFF;
            }
            else
            {
                if (i + 1 >= end) break;
                int b1 = src[i], b2 = src[i + 1]; i += 2;
                int p = b1 | ((b2 & 0xF0) << 4);
                int len = (b2 & 0x0F) + 3;
                for (int k = 0; k < len && n < outSize; k++)
                {
                    byte c = win[(p + k) & 0xFFF];
                    outBuf[n++] = c; win[r] = c; r = (r + 1) & 0xFFF;
                }
            }
        }
        if (n == outSize) return outBuf;
        byte[] cut = new byte[n];
        Array.Copy(outBuf, cut, n);
        return cut;
    }

    static List<byte[]> LinkEntries(byte[] d)
    {
        List<byte[]> result = new List<byte[]>();
        if (d.Length < 8 || d[0] != 'L' || d[1] != 'I' || d[2] != 'N' || d[3] != 'K') return result;
        int count = d[4];
        for (int k = 0; k < count; k++)
        {
            int e = 8 + 16 * k;
            if (e + 16 > d.Length) break;
            int off = (int)U32(d, e + 4), size = (int)U32(d, e + 8);
            if (off < 0 || size <= 0 || off + size > d.Length) continue;
            if (size >= 16 && d[off] == 'C' && d[off + 1] == 'P' && d[off + 2] == 'K')
            {
                int usize = (int)U32(d, off + 8);
                if (d[off + 3] == '0')
                {
                    result.Add(Lzss(d, off + 16, off + size, usize));
                }
                else
                {
                    byte[] raw = new byte[Math.Min(usize, size - 16)];
                    Array.Copy(d, off + 16, raw, 0, raw.Length);
                    result.Add(raw);
                }
            }
            else
            {
                byte[] raw = new byte[size];
                Array.Copy(d, off, raw, 0, size);
                result.Add(raw);
            }
        }
        return result;
    }

    static void WriteElf(byte[] img, uint load, string path)
    {
        byte[] shstr = Encoding.ASCII.GetBytes("\0.text\0.shstrtab\0");
        int offData = 0x1000;
        int offShstr = offData + img.Length;
        int offSh = (offShstr + shstr.Length + 3) & ~3;
        using (BinaryWriter w = new BinaryWriter(File.Create(path)))
        {
            w.Write(new byte[] { 0x7F, (byte)'E', (byte)'L', (byte)'F', 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0 });
            w.Write((ushort)2); w.Write((ushort)8); w.Write(1u); w.Write(load + 0x80u); w.Write(52u);
            w.Write((uint)offSh); w.Write(0x20924001u); w.Write((ushort)52); w.Write((ushort)32); w.Write((ushort)1);
            w.Write((ushort)40); w.Write((ushort)3); w.Write((ushort)2);
            // program header
            w.Write(1u); w.Write((uint)offData); w.Write(load); w.Write(load); w.Write((uint)img.Length);
            w.Write((uint)img.Length); w.Write(7u); w.Write(0x10u);
            w.Write(new byte[offData - 52 - 32]);
            w.Write(img);
            w.Write(shstr);
            w.Write(new byte[offSh - offShstr - shstr.Length]);
            w.Write(new byte[40]);
            w.Write(1u); w.Write(1u); w.Write(6u); w.Write(load); w.Write((uint)offData); w.Write((uint)img.Length);
            w.Write(0u); w.Write(0u); w.Write(16u); w.Write(0u);
            w.Write(7u); w.Write(3u); w.Write(0u); w.Write(0u); w.Write((uint)offShstr); w.Write((uint)shstr.Length);
            w.Write(0u); w.Write(0u); w.Write(1u); w.Write(0u);
        }
    }

    // Function-start hints: JAL targets, prologues, and code pointers to a prologue or to code that
    // follows a "jr ra" (leaf functions).
    static List<uint> Seeds(byte[] img, uint load)
    {
        return Seeds(img, load, null);
    }

    static List<uint> Seeds(byte[] img, uint load, ICollection<uint> external)
    {
        int words = img.Length / 4;
        uint[] w = new uint[words];
        for (int i = 0; i < words; i++) w[i] = U32(img, i * 4);
        uint end = load + (uint)img.Length;
        SortedSet<uint> s = new SortedSet<uint>();
        for (int i = 0; i < words; i++)
        {
            uint a = load + (uint)i * 4;
            if (a < load + 0x80) continue;
            uint v = w[i];
            if ((v >> 26) == 3)
            {
                uint t = ((a + 4) & 0xF0000000u) | ((v & 0x3FFFFFFu) << 2);
                if (t >= load + 0x80 && t < end) s.Add(t);
            }
            if ((v & 0xFFFF8000u) == 0x27BD8000u) s.Add(a);
            if (v >= load + 0x80 && v < end && (v & 3) == 0)
            {
                int j = (int)((v - load) / 4);
                bool prologue = false;
                for (int k = 0; k < 3; k++)
                {
                    if (j + k < words && (w[j + k] & 0xFFFF8000u) == 0x27BD8000u) { prologue = true; break; }
                }
                if (prologue) { s.Add(v); continue; }
                // Leaf function: the code before it (skipping nop padding) ends with jr ra + delay slot.
                int b = j - 1, pad = 0;
                while (b >= 0 && w[b] == 0 && pad < 4) { b--; pad++; }
                if (b - 1 >= 0 && w[b - 1] == 0x03E00008u && j < words && w[j] != 0) s.Add(v);
            }
        }
        // Addresses the main ELF jumps to or points at inside this module, when they look like the
        // start of a function (prologue, or right after the previous function's "jr ra").
        if (external != null)
        {
            foreach (uint v in external)
            {
                if (v < load + 0x80 || v >= end || (v & 3) != 0) continue;
                int j = (int)((v - load) / 4);
                if (w[j] == 0) continue;
                bool ok = false;
                for (int k = 0; k < 3 && !ok; k++) ok = j + k < words && (w[j + k] & 0xFFFF8000u) == 0x27BD8000u;
                if (!ok)
                {
                    int b = j - 1, pad = 0;
                    while (b >= 0 && w[b] == 0 && pad < 4) { b--; pad++; }
                    ok = b - 1 >= 0 && w[b - 1] == 0x03E00008u;
                }
                if (ok) s.Add(v);
            }
        }
        return s.ToList();
    }

    // J/JAL targets and pointer-sized words in the main ELF that fall in the overlay area.
    static HashSet<uint> MainReferences(string mainElf)
    {
        HashSet<uint> refs = new HashSet<uint>();
        if (string.IsNullOrEmpty(mainElf)) return refs;
        uint va, memsz;
        byte[] text = LoadSegment(mainElf, true, out va, out memsz);
        for (int i = 0; i + 4 <= text.Length; i += 4)
        {
            uint v = U32(text, i);
            uint op = v >> 26;
            if (op == 2 || op == 3)
            {
                uint t = ((va + (uint)i + 4) & 0xF0000000u) | ((v & 0x3FFFFFFu) << 2);
                if (t >= 0x00C00000u && t < 0x01000000u) refs.Add(t);
            }
            if (v >= 0x00C00000u && v < 0x01000000u && (v & 3) == 0) refs.Add(v);
        }
        return refs;
    }

    public static int Extract(string afsPath, string workDir)
    {
        return Extract(afsPath, workDir, null);
    }

    public static int Extract(string afsPath, string workDir, string mainElf)
    {
        HashSet<uint> mainRefs = MainReferences(mainElf);
        string elfDir = Path.Combine(workDir, "elf"), seedDir = Path.Combine(workDir, "seeds");
        Directory.CreateDirectory(elfDir);
        Directory.CreateDirectory(seedDir);
        HashSet<string> seen = new HashSet<string>();
        using (FileStream f = File.OpenRead(afsPath))
        using (BinaryReader r = new BinaryReader(f))
        {
            byte[] magic = r.ReadBytes(4);
            if (magic[0] != 'A' || magic[1] != 'F' || magic[2] != 'S') throw new Exception("not an AFS archive: " + afsPath);
            int count = r.ReadInt32();
            uint[] off = new uint[count], size = new uint[count];
            for (int i = 0; i < count; i++) { off[i] = r.ReadUInt32(); size[i] = r.ReadUInt32(); }
            uint nameOff = r.ReadUInt32();
            r.ReadUInt32();
            string[] names = new string[count];
            f.Position = nameOff;
            for (int i = 0; i < count; i++)
            {
                byte[] e = r.ReadBytes(48);
                int z = Array.IndexOf(e, (byte)0);
                names[i] = Encoding.ASCII.GetString(e, 0, (z < 0 || z > 32) ? 32 : z);
            }
            for (int i = 0; i < count; i++)
            {
                if (!names[i].EndsWith(".ldt", StringComparison.OrdinalIgnoreCase) || size[i] == 0) continue;
                f.Position = off[i];
                byte[] d = r.ReadBytes((int)size[i]);
                foreach (byte[] img in LinkEntries(d))
                {
                    if (img.Length < 0x80 || img[0] != 'M' || img[1] != 'W' || img[2] != 'o' || img[3] != '3') continue;
                    uint load = U32(img, 8);
                    int z = Array.IndexOf(img, (byte)0, 0x20, 0x20);
                    string name = Encoding.ASCII.GetString(img, 0x20, (z < 0 ? 0x40 : z) - 0x20).Replace(".bin", "");
                    if (name.Length == 0 || !seen.Add(name)) continue;
                    WriteElf(img, load, Path.Combine(elfDir, name + ".elf"));
                    File.WriteAllText(Path.Combine(seedDir, name + ".seeds"),
                        string.Join("\n", Seeds(img, load, mainRefs).Select(x => "0x" + x.ToString("x8")).ToArray()));
                }
            }
        }
        return seen.Count;
    }

    const string Header =
        "// Generated from a recompiled overlay module. Do not edit.\n" +
        "#include <cmath>\n#include <stdexcept>\n" +
        "#include \"ps2_runtime_macros.h\"\n#include \"ps2_runtime.h\"\n#include \"ps2_syscalls.h\"\n#include \"ps2_stubs.h\"\n" +
        "#ifdef PS2_FUNCTION_LOG_TRACKER\n#include \"ps2_log.h\"\n#endif\nusing std::isnan;\n";

    // Code segment of an ELF: the first PT_LOAD (overlay modules), or the one holding the entry point.
    static byte[] LoadSegment(string elfPath, bool containingEntry, out uint vaddr, out uint memsz)
    {
        byte[] d = File.ReadAllBytes(elfPath);
        uint entry = U32(d, 24);
        int phoff = (int)U32(d, 28);
        int phnum = BitConverter.ToUInt16(d, 44);
        for (int k = 0; k < phnum; k++)
        {
            int ph = phoff + 32 * k;
            int off = (int)U32(d, ph + 4);
            uint va = U32(d, ph + 8);
            int filesz = (int)U32(d, ph + 16);
            if (!containingEntry || (entry >= va && entry < va + (uint)filesz))
            {
                vaddr = va;
                memsz = U32(d, ph + 20);
                byte[] image = new byte[filesz];
                Array.Copy(d, off, image, 0, filesz);
                return image;
            }
        }
        throw new Exception("no code segment in " + elfPath);
    }

    // Addresses in the main ELF's code that overlay modules jump to (J/JAL), or that code pointers
    // lead to, but that have no entry in the main recompiled function table. Writes a ps2_recomp CSV for them (plus the ELF entry
    // function, which ps2_recomp requires): each covers the rest of the function that contains it in
    // the main function CSV, or runs to the next "jr ra" if no function does.
    public static int MainExtra(string registerCpp, string functionsCsv, string mainElf, string elfDir, string outCsv)
    {
        string reg = File.ReadAllText(registerCpp);
        uint tableBase = Convert.ToUInt32(Regex.Match(reg, @"TableBase = (0x[0-9a-fA-F]+)u").Groups[1].Value, 16);
        uint tableEnd = Convert.ToUInt32(Regex.Match(reg, @"TableEnd = (0x[0-9a-fA-F]+)u").Groups[1].Value, 16);
        HashSet<uint> have = new HashSet<uint>();
        foreach (Match m in Regex.Matches(reg, @"g_ps2RecompiledFunctionTable\[(\d+)\] ="))
        {
            have.Add(tableBase + uint.Parse(m.Groups[1].Value) * 4);
        }

        SortedSet<uint> targets = new SortedSet<uint>();
        foreach (string elf in Directory.GetFiles(elfDir, "*.elf"))
        {
            uint load, memsz;
            byte[] img = LoadSegment(elf, false, out load, out memsz);
            for (int i = 0x80; i + 4 <= img.Length; i += 4)
            {
                uint w = U32(img, i);
                uint op = w >> 26;
                if (op != 2 && op != 3) continue;
                uint t = ((load + (uint)i + 4) & 0xF0000000u) | ((w & 0x3FFFFFFu) << 2);
                if (t >= tableBase && t < tableEnd && !have.Contains(t)) targets.Add(t);
            }
        }

        List<uint[]> ranges = new List<uint[]>();
        string entryRow = null;
        uint textBase, textSize;
        byte[] text = LoadSegment(mainElf, true, out textBase, out textSize);
        uint elfEntry = U32(File.ReadAllBytes(mainElf), 24);
        foreach (string line in File.ReadAllLines(functionsCsv).Skip(1))
        {
            string[] f = line.Split(',');
            if (f.Length < 3) continue;
            uint start = Convert.ToUInt32(f[1], 16), end = Convert.ToUInt32(f[2], 16);
            ranges.Add(new uint[] { start, end });
            if (start == elfEntry && entryRow == null) entryRow = line;
        }

        // Code pointers: words in the main ELF or a module image that point at the start of a gap
        // Ghidra left between functions (only nop padding before it), e.g. callbacks that are only
        // reached through function pointers. Such a target covers the gap up to the next function.
        ranges.Sort((x, y) => x[0].CompareTo(y[0]));
        List<uint[]> covered = new List<uint[]>();
        foreach (uint[] r in ranges)
        {
            if (covered.Count > 0 && r[0] <= covered[covered.Count - 1][1])
            {
                if (r[1] > covered[covered.Count - 1][1]) covered[covered.Count - 1][1] = r[1];
            }
            else covered.Add(new uint[] { r[0], r[1] });
        }
        uint[] coveredStarts = covered.Select(c => c[0]).ToArray();
        Dictionary<uint, uint> gapEnds = new Dictionary<uint, uint>();
        Func<uint, uint> textWord = a => U32(text, (int)(a - textBase));
        Action<byte[]> scanPointers = img =>
        {
            for (int i = 0; i + 4 <= img.Length; i += 4)
            {
                uint v = U32(img, i);
                if (v < tableBase || v >= tableEnd || (v & 3) != 0 || have.Contains(v) || gapEnds.ContainsKey(v)) continue;
                int k = Array.BinarySearch(coveredStarts, v);
                if (k < 0) k = ~k - 1;
                if (k < 0) continue;
                if (v < covered[k][1]) continue; // inside an analysed function
                uint gapStart = covered[k][1];
                uint gapEnd = (k + 1 < covered.Count) ? covered[k + 1][0] : tableEnd;
                if (v - gapStart > 0x40 || textWord(v) == 0) continue;
                bool padding = true;
                for (uint a = gapStart; a < v; a += 4) { if (textWord(a) != 0) { padding = false; break; } }
                if (!padding) continue;
                gapEnds[v] = Math.Min(gapEnd, v + 0x4000u);
            }
        };
        scanPointers(text);
        foreach (string elf in Directory.GetFiles(elfDir, "*.elf"))
        {
            uint load, memsz;
            scanPointers(LoadSegment(elf, false, out load, out memsz));
        }
        foreach (KeyValuePair<uint, uint> g in gapEnds) targets.Add(g.Key);

        StringBuilder csv = new StringBuilder("Name,Start,End,Size\n");
        int count = 0;
        foreach (uint t in targets)
        {
            if (gapEnds.ContainsKey(t))
            {
                uint gEnd = gapEnds[t];
                csv.AppendFormat("extra_{0:x8},0x{0:X8},0x{1:X8},{2}\n", t, gEnd, gEnd - t);
                count++;
                continue;
            }
            uint end = 0;
            foreach (uint[] r in ranges)
            {
                if (r[0] <= t && t < r[1] && r[1] > end) end = r[1];
            }
            if (end == 0 || end - t > 0x4000u)
            {
                end = 0;
                for (uint a = t; a + 8 <= textBase + (uint)text.Length && a < t + 0x4000u; a += 4)
                {
                    if (U32(text, (int)(a - textBase)) == 0x03E00008u) { end = a + 8; break; }
                }
            }
            if (end <= t) continue;
            csv.AppendFormat("extra_{0:x8},0x{0:X8},0x{1:X8},{2}\n", t, end, end - t);
            count++;
        }
        if (entryRow != null) csv.Append(entryRow).Append('\n');
        File.WriteAllText(outCsv, csv.ToString());
        return count;
    }

    public static string Generate(string recompDir, string elfPath, string destDir)
    {
        return Generate(recompDir, elfPath, destDir, false);
    }

    public static string Generate(string recompDir, string elfPath, string destDir, bool mainExtra)
    {
        uint vaddr, memsz;
        byte[] image = LoadSegment(elfPath, mainExtra, out vaddr, out memsz);
        int filesz = image.Length;
        string name, ident;
        if (mainExtra)
        {
            name = Path.GetFileName(elfPath) + " (extra entry points)";
            ident = "main_extra";
            memsz = (uint)filesz;
        }
        else
        {
            int z = Array.IndexOf(image, (byte)0, 0x20, 0x20);
            name = Encoding.ASCII.GetString(image, 0x20, (z < 0 ? 0x40 : z) - 0x20);
            ident = Regex.Replace(name.Replace(".bin", ""), "[^A-Za-z0-9]", "_");
        }
        string ns = "ps2ovl_" + ident;
        Directory.CreateDirectory(destDir);

        List<string> bodies = new List<string>();
        List<string> fnames = new List<string>();
        Regex def = new Regex(@"^void (\w+)\(uint8_t\* rdram, R5900Context\* ctx, PS2Runtime \*runtime\) \{", RegexOptions.Multiline);
        string[] files = Directory.GetFiles(recompDir, "*.cpp");
        Array.Sort(files, StringComparer.Ordinal);
        foreach (string file in files)
        {
            if (Path.GetFileName(file) == "register_functions.cpp") continue;
            string t = File.ReadAllText(file).Replace("\r\n", "\n");
            int i = t.IndexOf("// Function: ", StringComparison.Ordinal);
            if (i < 0) continue;
            string body = t.Substring(i);
            foreach (Match m in def.Matches(body)) fnames.Add(m.Groups[1].Value);
            bodies.Add(body);
        }

        StringBuilder decl = new StringBuilder();
        foreach (string n in fnames) decl.Append("void ").Append(n).Append("(uint8_t* rdram, R5900Context* ctx, PS2Runtime *runtime);\n");

        List<string> written = new List<string>();
        int chunk = 0, size = 0;
        StringBuilder cur = new StringBuilder();
        Action flush = () =>
        {
            if (cur.Length == 0) return;
            string fn = Path.Combine(destDir, string.Format("ovl_{0}_{1:D3}.cpp", ident, chunk++));
            File.WriteAllText(fn, Header + "\nnamespace " + ns + "\n{\n" + decl + "\n" + cur + "\n} // namespace " + ns + "\n");
            written.Add(fn);
            cur.Clear();
            size = 0;
        };
        foreach (string b in bodies)
        {
            cur.Append(b).Append('\n');
            size += b.Length;
            if (size >= 1500000) flush();
        }
        flush();

        string reg = File.ReadAllText(Path.Combine(recompDir, "register_functions.cpp"));
        uint tableBase = Convert.ToUInt32(Regex.Match(reg, @"TableBase = (0x[0-9a-fA-F]+)u").Groups[1].Value, 16);
        SortedDictionary<uint, string> entries = new SortedDictionary<uint, string>();
        foreach (Match m in Regex.Matches(reg, @"g_ps2RecompiledFunctionTable\[(\d+)\] = (\w+);"))
        {
            entries[tableBase + uint.Parse(m.Groups[1].Value) * 4] = m.Groups[2].Value;
        }
        HashSet<string> known = new HashSet<string>(fnames);
        foreach (string fn in entries.Values)
        {
            if (!known.Contains(fn)) throw new Exception(name + ": table references unknown function " + fn);
        }

        StringBuilder o = new StringBuilder();
        o.Append("// Generated overlay module table. Do not edit.\n#include \"ps2_overlays.h\"\n\n");
        o.Append("namespace ").Append(ns).Append("\n{\n").Append(decl);
        o.Append("\nnamespace\n{\n    const PS2OverlayFunction kFunctions[] = {\n");
        foreach (KeyValuePair<uint, string> e in entries)
        {
            o.AppendFormat("        {{0x{0:X8}u, &{1}}},\n", e.Key, e.Value);
        }
        o.Append("    };\n    const uint8_t kSignature[] = {");
        int sigBytes = Math.Min(0xC0, image.Length);
        for (int i = 0; i < sigBytes; i++) { if (i > 0) o.Append(','); o.Append(image[i]); }
        o.Append("};\n");
        o.AppendFormat("    const PS2OverlayModule kModule = {{\"{0}\", 0x{1:X8}u, 0x{2:X}u, kSignature, sizeof(kSignature), kFunctions, sizeof(kFunctions) / sizeof(kFunctions[0])}};\n",
                       name, vaddr, Math.Max((uint)filesz, memsz));
        o.Append("    struct Registration\n    {\n        Registration() { ps2xRegisterOverlayModule(&kModule); }\n    } s_registration;\n}\n");
        o.Append("} // namespace ").Append(ns).Append("\n");
        File.WriteAllText(Path.Combine(destDir, "ovl_" + ident + "_table.cpp"), o.ToString());
        return string.Format("{0}: {1} functions, {2} entry points, {3} chunk(s)", name, fnames.Count, entries.Count, written.Count);
    }
}
'@

if (-not ('O3Overlays' -as [type])) {
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        # Windows PowerShell 5.1: the C# above uses LINQ (System.Core).
        Add-Type -TypeDefinition $source -Language CSharp -ReferencedAssemblies System.Core
    } else {
        Add-Type -TypeDefinition $source -Language CSharp
    }
}

if ($Extract) {
    # optional 3rd argument: the main ELF, whose jumps/pointers into the overlay area add function seeds
    $main = $null; if ($C) { $main = (Resolve-Path $C).Path }
    $n = [O3Overlays]::Extract((Resolve-Path $A).Path, [IO.Path]::GetFullPath($B), $main)
    Write-Host "Extracted $n code modules."
}
elseif ($Generate) {
    $recomp = [IO.Path]::GetFullPath($A); $elfDir = [IO.Path]::GetFullPath($B); $dest = [IO.Path]::GetFullPath($C)
    if (Test-Path $dest) { Remove-Item (Join-Path $dest 'ovl_*.cpp') -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $failed = 0
    foreach ($elf in Get-ChildItem $elfDir -Filter *.elf | Sort-Object Name) {
        $dir = Join-Path $recomp $elf.BaseName
        if (-not (Test-Path (Join-Path $dir 'register_functions.cpp'))) { Write-Host "skipped $($elf.BaseName) (not recompiled)"; $failed++; continue }
        Write-Host ([O3Overlays]::Generate($dir, $elf.FullName, $dest))
    }
    # Optional 4th argument: the main ELF, whose extra entry points were recompiled to <recompDir>\main_extra
    if ($D) {
        $dir = Join-Path $recomp 'main_extra'
        if (Test-Path (Join-Path $dir 'register_functions.cpp')) {
            Write-Host ([O3Overlays]::Generate($dir, [IO.Path]::GetFullPath($D), $dest, $true))
        } else { Write-Host 'skipped main_extra (not recompiled)'; $failed++ }
    }
    if ($failed) { exit 1 }
}
elseif ($MainExtra) {
    # -MainExtra <output\register_functions.cpp> <functions.csv> <SLUS_206.94> <elfDir> <outCsv>
    $n = [O3Overlays]::MainExtra([IO.Path]::GetFullPath($A), [IO.Path]::GetFullPath($B), [IO.Path]::GetFullPath($C), [IO.Path]::GetFullPath($D), [IO.Path]::GetFullPath($E))
    Write-Host "$n main-ELF entry points are only reached from overlays."
}
elseif ($GhidraScript) {
    $t = Get-Content -Raw $A
    $t = $t.Replace('public class ExportPS2Functions', 'public class ExportPS2Overlay')
    $t = $t.Replace('File tomlFile = askFile("Choose output TOML config file", "Save");',
        'File outDir = new File(getScriptArgs()[0]); String base = new File(currentProgram.getExecutablePath()).getName().replaceAll("\\.elf$", ""); File tomlFile = new File(outDir, base + ".toml");')
    $t = $t.Replace('File csvFile = askFile("Choose output CSV file", "Save");', 'File csvFile = new File(outDir, base + ".csv");')
    if ($t -notmatch 'class ExportPS2Overlay' -or $t -notmatch 'new File\(outDir, base \+ ".csv"\)') { throw 'ExportPS2Functions.java has changed; cannot derive ExportPS2Overlay.java' }
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($B), $t)
}
else {
    Write-Host 'usage: overlays.ps1 -Extract <IMAGE.AFS> <workDir> | -MainExtra <register_functions.cpp> <functions.csv> <elf> <elfDir> <outCsv> | -Generate <recompDir> <elfDir> <destDir> [<mainElf>] | -GhidraScript <ExportPS2Functions.java> <out>'
    exit 2
}

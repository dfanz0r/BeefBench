using System;
using System.Collections;
using System.Text;

namespace Benchmarks.Framework;

struct Color
{
    public uint8 R;
    public uint8 G;
    public uint8 B;

    public this(uint8 r, uint8 g, uint8 b)
    {
        R = r; G = g; B = b;
    }

    public static Color FromHex(int32 hex)
    {
        return .((uint8)((hex >> 16) & 0xFF), (uint8)((hex >> 8) & 0xFF), (uint8)(hex & 0xFF));
    }
}

static class Theme
{
    public static Color Primary = .FromHex(0x00f2ff);   // Neon Blue
    public static Color Secondary = .FromHex(0xff0099); // Neon Pink
    public static Color Success = .FromHex(0x00ff9d);   // Neon Green
    public static Color Text = .FromHex(0xffffff);      // White
    public static Color Muted = .FromHex(0x666666);     // Gray
    public static Color Background = .FromHex(0x1a1a1a); // Dark Gray
    public static Color Border = .FromHex(0x444444);    // Darker Gray
}

static class Ansi
{
    public const String Reset = "\x1b[0m";
    public const String Bold = "\x1b[1m";
    public const String HideCursor = "\x1b[?25l";
    public const String ShowCursor = "\x1b[?25h";

    public static void Color(String sb, Color c, bool bg = false)
    {
        sb.Append("\x1b[");
        sb.Append(bg ? "48" : "38");
        sb.Append(";2;");
        sb.Append(c.R);
        sb.Append(";");
        sb.Append(c.G);
        sb.Append(";");
        sb.Append(c.B);
        sb.Append("m");
    }

    public static int VisibleLength(StringView str)
    {
        int len = 0;
        bool inEscape = false;
        for (char8 c in str)
        {
            if (c == '\x1b')
            {
                inEscape = true;
                continue;
            }
            if (inEscape)
            {
                if (c == 'm') inEscape = false;
                continue;
            }
            len++;
        }
        return len;
    }
}

static class Cursor
{
    public static void Up(int n = 1) => Console.Write(scope String()..AppendF($"\x1b[{n}A"));
    public static void Down(int n = 1) => Console.Write(scope String()..AppendF($"\x1b[{n}B"));
    public static void Right(int n = 1) => Console.Write(scope String()..AppendF($"\x1b[{n}C"));
    public static void Left(int n = 1) => Console.Write(scope String()..AppendF($"\x1b[{n}D"));
    public static void MoveTo(int row, int col) => Console.Write(scope String()..AppendF($"\x1b[{row};{col}H"));
    public static void ClearLine() => Console.Write("\x1b[2K\r");
    public static void Hide() => Console.Write(Ansi.HideCursor);
    public static void Show() => Console.Write(Ansi.ShowCursor);
}

class LogWindow
{
    int mHeight;
    List<String> mLines = new .() ~ DeleteContainerAndItems!(_);

    public this(int height)
    {
        mHeight = height;
    }

    public void AddLine(StringView text)
    {
        if (mLines.Count >= mHeight)
        {
            delete mLines[0];
            mLines.RemoveAt(0);
        }
        mLines.Add(new String(text));
    }

    public void ReplaceLastLine(StringView text)
    {
        if (mLines.Count > 0)
        {
            delete mLines[mLines.Count - 1];
            mLines[mLines.Count - 1] = new String(text);
        }
        else
        {
            AddLine(text);
        }
    }

    public void Render()
    {
        for (int i = 0; i < mHeight; i++)
        {
            Cursor.ClearLine();
            if (i < mLines.Count)
            {
                Console.WriteLine(mLines[i]);
            }
            else
            {
                Console.WriteLine();
            }
        }
    }
}

class ProgressBar
{
    public int Width = 50;
    
    public void Render(double progress, StringView message)
    {
        Cursor.ClearLine();
        String sb = scope .();
        
        int filled = (int)(Width * progress);
        int empty = Width - filled;
        
        Ansi.Color(sb, Theme.Success);
        sb.Append('█', filled);
        Ansi.Color(sb, Theme.Muted);
        sb.Append('░', empty);
        sb.Append(Ansi.Reset);
        
        sb.Append(" ");
        Ansi.Color(sb, Theme.Primary);
        sb.AppendF($"{progress * 100:F0}% ");
        sb.Append(Ansi.Reset);
        
        Ansi.Color(sb, Theme.Muted);
        sb.Append(message);
        sb.Append(Ansi.Reset);
        
        Console.Write(sb);
    }
}

static class Box
{
    public const String Horizontal = "─";
    public const String Vertical = "│";
    public const String TopLeft = "╭";
    public const String TopRight = "╮";
    public const String BottomLeft = "╰";
    public const String BottomRight = "╯";
    public const String Cross = "┼";
    public const String TeeLeft = "├";
    public const String TeeRight = "┤";
    public const String TeeTop = "┬";
    public const String TeeBottom = "┴";
}

class Table
{
    class Column
    {
        public String Header;
        public int Width;
        public bool RightAlign;

        public this(String header, bool rightAlign = false)
        {
            Header = new String(header);
            RightAlign = rightAlign;
            Width = header.Length;
        }

        public ~this() { delete Header; }
    }

    List<Column> mColumns = new .() ~ DeleteContainerAndItems!(_);
    List<List<String>> mRows = new .();

    public ~this()
    {
        for (let row in mRows)
        {
            DeleteContainerAndItems!(row);
        }
        delete mRows;
    }

    public void AddColumn(String header, bool rightAlign = false)
    {
        mColumns.Add(new .(header, rightAlign));
    }

    public void AddRow(params String[] cells)
    {
        var row = new List<String>();
        for (int i = 0; i < cells.Count; i++)
        {
            String cell = new String(cells[i]);
            row.Add(cell);
            
            if (i < mColumns.Count)
            {
                mColumns[i].Width = Math.Max(mColumns[i].Width, Ansi.VisibleLength(cell));
            }
        }
        mRows.Add(row);
    }

    public void Render()
    {
        String sb = scope .();
        
        // Top Border
        Ansi.Color(sb, Theme.Border);
        sb.Append(Box.TopLeft);
        for (int i = 0; i < mColumns.Count; i++)
        {
            for (int j = 0; j < mColumns[i].Width + 2; j++) sb.Append(Box.Horizontal);
            if (i < mColumns.Count - 1) sb.Append(Box.TeeTop);
        }
        sb.Append(Box.TopRight);
        sb.Append(Ansi.Reset);
        sb.Append('\n');

        // Header
        Ansi.Color(sb, Theme.Border);
        sb.Append(Box.Vertical);
        sb.Append(Ansi.Reset);
        for (int i = 0; i < mColumns.Count; i++)
        {
            sb.Append(" ");
            Ansi.Color(sb, Theme.Primary);
            sb.Append(Ansi.Bold);
            AppendPadded(sb, mColumns[i].Header, mColumns[i].Width, mColumns[i].RightAlign);
            sb.Append(Ansi.Reset);
            sb.Append(" ");
            Ansi.Color(sb, Theme.Border);
            sb.Append(Box.Vertical);
            sb.Append(Ansi.Reset);
        }
        sb.Append('\n');

        // Separator
        Ansi.Color(sb, Theme.Border);
        sb.Append(Box.TeeLeft);
        for (int i = 0; i < mColumns.Count; i++)
        {
            for (int j = 0; j < mColumns[i].Width + 2; j++) sb.Append(Box.Horizontal);
            if (i < mColumns.Count - 1) sb.Append(Box.Cross);
        }
        sb.Append(Box.TeeRight);
        sb.Append(Ansi.Reset);
        sb.Append('\n');

        // Rows
        for (let row in mRows)
        {
            Ansi.Color(sb, Theme.Border);
            sb.Append(Box.Vertical);
            sb.Append(Ansi.Reset);
            for (int i = 0; i < mColumns.Count; i++)
            {
                String cell = (i < row.Count) ? row[i] : "";
                sb.Append(" ");
                Ansi.Color(sb, Theme.Text);
                AppendPadded(sb, cell, mColumns[i].Width, mColumns[i].RightAlign);
                sb.Append(Ansi.Reset);
                sb.Append(" ");
                Ansi.Color(sb, Theme.Border);
                sb.Append(Box.Vertical);
                sb.Append(Ansi.Reset);
            }
            sb.Append('\n');
        }

        // Bottom Border
        Ansi.Color(sb, Theme.Border);
        sb.Append(Box.BottomLeft);
        for (int i = 0; i < mColumns.Count; i++)
        {
            for (int j = 0; j < mColumns[i].Width + 2; j++) sb.Append(Box.Horizontal);
            if (i < mColumns.Count - 1) sb.Append(Box.TeeBottom);
        }
        sb.Append(Box.BottomRight);
        sb.Append(Ansi.Reset);
        sb.Append('\n');

        Console.Write(sb);
    }

    private void AppendPadded(String sb, String str, int width, bool rightAlign)
    {
        int visibleLen = Ansi.VisibleLength(str);
        int padding = width - visibleLen;
        
        if (padding <= 0)
        {
            sb.Append(str);
            return;
        }

        if (rightAlign)
        {
            sb.Append(' ', padding);
            sb.Append(str);
        }
        else
        {
            sb.Append(str);
            sb.Append(' ', padding);
        }
    }
}

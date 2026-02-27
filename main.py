import customtkinter as ctk
from tkinter import ttk
import tkinter as tk

# ─────────────────────────────────────────────
# Theme & Constants
# ─────────────────────────────────────────────
ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("blue")

COLORS = {
    "bg":        "#0f1117",
    "panel":     "#1a1d27",
    "card":      "#22263a",
    "accent":    "#4f8ef7",
    "accent2":   "#38d9a9",
    "danger":    "#f76f6f",
    "text":      "#e8eaf6",
    "subtext":   "#8b91b0",
    "border":    "#2e3350",
    "row_even":  "#1e2235",
    "row_odd":   "#181c2e",
    "row_total": "#252a45",
}

FONT_TITLE  = ("Helvetica Neue", 22, "bold")
FONT_HEAD   = ("Helvetica Neue", 13, "bold")
FONT_BODY   = ("Helvetica Neue", 12)
FONT_SMALL  = ("Helvetica Neue", 11)
FONT_MONO   = ("Courier New", 12)

MODES = {
    "ทบต้นรายวัน (Daily)":          (365, "วัน",     "ทบดอกทุกวัน"),
    "ทบต้นรายสัปดาห์ (Weekly)":     (52,  "สัปดาห์", "ทบดอกทุกสัปดาห์"),
    "ทบต้นรายเดือน (Monthly)":      (12,  "เดือน",   "ทบดอกทุกเดือน"),
    "ทบต้นราย 2 เดือน (Bi-Monthly)":(6,   "งวด",     "ทบดอกทุก 2 เดือน"),
    "ทบต้นรายไตรมาส (Quarterly)":   (4,   "ไตรมาส",  "ทบดอกทุก 3 เดือน"),
    "ทบต้นรายครึ่งปี (Semi-Annual)": (2,   "ครึ่งปี", "ทบดอกทุก 6 เดือน"),
    "ทบต้นรายปี (Annual)":          (1,   "ปี",      "ทบดอกทุกปี"),
    "ดอกเบี้ยธรรมดา (Simple)":      (0,   "งวด",     "ไม่ทบต้น คิดดอกจากเงินต้นตลอด"),
}


# ─────────────────────────────────────────────
# Reusable Widget Helpers
# ─────────────────────────────────────────────
def labeled_entry(parent, label: str, placeholder: str = "") -> ctk.CTkEntry:
    ctk.CTkLabel(
        parent, text=label,
        font=FONT_SMALL, text_color=COLORS["subtext"],
        anchor="w"
    ).pack(fill="x", padx=4, pady=(10, 2))
    entry = ctk.CTkEntry(
        parent,
        placeholder_text=placeholder,
        font=FONT_BODY, height=38, corner_radius=8,
        border_width=1, border_color=COLORS["border"],
        fg_color=COLORS["card"], text_color=COLORS["text"],
    )
    entry.pack(fill="x", padx=4, pady=(0, 2))
    return entry


def stat_card(parent, title: str, value_var: tk.StringVar, accent: str) -> ctk.CTkFrame:
    card = ctk.CTkFrame(parent, fg_color=COLORS["card"], corner_radius=10)
    card.pack(fill="x", padx=0, pady=4)
    ctk.CTkLabel(card, text=title, font=FONT_SMALL,
                 text_color=COLORS["subtext"]).pack(anchor="w", padx=14, pady=(10, 0))
    ctk.CTkLabel(card, textvariable=value_var, font=("Helvetica Neue", 16, "bold"),
                 text_color=accent).pack(anchor="w", padx=14, pady=(2, 10))
    return card


# ─────────────────────────────────────────────
# Main Application
# ─────────────────────────────────────────────
class FinanceApp(ctk.CTk):

    def __init__(self):
        super().__init__()
        self.title("Finance Calculator Pro")
        self.geometry("1150x700")
        self.minsize(960, 580)
        self.configure(fg_color=COLORS["bg"])
        self._build_layout()
        self._style_treeview()

    # ── Layout ───────────────────────────────
    def _build_layout(self):
        header = ctk.CTkFrame(self, fg_color=COLORS["panel"], height=56, corner_radius=0)
        header.pack(fill="x", side="top")

        # ✅ ลบ emoji 💹 ออก → Tcl บน Windows ไม่รองรับ Unicode นอก BMP (U+0000-U+FFFF)
        ctk.CTkLabel(header, text="Finance Calculator 17 Pro Max 256GB",
                     font=FONT_TITLE, text_color=COLORS["text"]).pack(side="left", padx=20, pady=10)
        ctk.CTkLabel(header, text="Compound & Simple Interest Analyzer",
                     font=FONT_SMALL, text_color=COLORS["subtext"]).pack(side="right", padx=20)

        body = ctk.CTkFrame(self, fg_color="transparent")
        body.pack(fill="both", expand=True, padx=16, pady=12)

        self._build_sidebar(body)
        self._build_main_panel(body)

    def _build_sidebar(self, parent):
        sidebar = ctk.CTkScrollableFrame(
            parent, width=280,
            fg_color=COLORS["panel"], corner_radius=12,
            scrollbar_button_color=COLORS["border"],
            scrollbar_button_hover_color=COLORS["accent"],
        )
        sidebar.pack(side="left", fill="y", padx=(0, 10))
        sidebar._scrollbar.configure(width=6)

        input_section = ctk.CTkFrame(sidebar, fg_color="transparent")
        input_section.pack(fill="x", padx=12, pady=(16, 0))

        ctk.CTkLabel(input_section, text="PARAMETERS",
                     font=("Helvetica Neue", 10, "bold"),
                     text_color=COLORS["subtext"]).pack(anchor="w", pady=(0, 8))

        self.entry_principal = labeled_entry(input_section, "เงินต้น (บาท)", "เช่น 100000")
        self.entry_rate      = labeled_entry(input_section, "อัตราดอกเบี้ยต่อปี (%)", "เช่น 5.5")
        self.entry_period    = labeled_entry(input_section, "จำนวนงวด", "เช่น 12")

        ctk.CTkLabel(input_section, text="รูปแบบการคิดดอกเบี้ย",
                     font=FONT_SMALL, text_color=COLORS["subtext"],
                     anchor="w").pack(fill="x", padx=4, pady=(10, 2))

        self.combo_mode = ctk.CTkComboBox(
            input_section,
            values=list(MODES.keys()),
            font=FONT_BODY, height=38, corner_radius=8,
            border_width=1, border_color=COLORS["border"],
            fg_color=COLORS["card"], text_color=COLORS["text"],
            button_color=COLORS["border"], dropdown_fg_color=COLORS["card"],
            command=self._on_mode_change,
        )
        self.combo_mode.pack(fill="x", padx=4, pady=(0, 2))
        self.combo_mode.set("ทบต้นรายเดือน (Monthly)")

        self.mode_desc_var = tk.StringVar(value="ทบดอกทุกเดือน")
        ctk.CTkLabel(input_section, textvariable=self.mode_desc_var,
                     font=("Helvetica Neue", 10), text_color=COLORS["accent2"],
                     anchor="w").pack(fill="x", padx=6, pady=(2, 0))

        self.error_var = tk.StringVar(value="")
        self.error_label = ctk.CTkLabel(input_section, textvariable=self.error_var,
                                        font=FONT_SMALL, text_color=COLORS["danger"],
                                        wraplength=240, justify="left")
        self.error_label.pack(anchor="w", padx=4, pady=(6, 0))

        ctk.CTkButton(
            input_section, text="คำนวณ",
            font=("Helvetica Neue", 14, "bold"),
            height=44, corner_radius=10,
            fg_color=COLORS["accent"], hover_color="#3a6fd8",
            command=self._on_calculate
        ).pack(fill="x", padx=4, pady=(16, 0))

        ctk.CTkButton(
            input_section, text="ล้างข้อมูล",
            font=FONT_SMALL, height=34, corner_radius=10,
            fg_color="transparent", border_width=1,
            border_color=COLORS["border"], text_color=COLORS["subtext"],
            hover_color=COLORS["card"],
            command=self._clear
        ).pack(fill="x", padx=4, pady=(6, 0))

        divider = ctk.CTkFrame(sidebar, fg_color=COLORS["border"], height=1)
        divider.pack(fill="x", padx=12, pady=(16, 10))

        summary_section = ctk.CTkFrame(sidebar, fg_color="transparent")
        summary_section.pack(fill="x", padx=12, pady=(0, 16))

        ctk.CTkLabel(summary_section, text="SUMMARY",
                     font=("Helvetica Neue", 10, "bold"),
                     text_color=COLORS["subtext"]).pack(anchor="w", pady=(0, 6))

        self.var_principal = tk.StringVar(value="-")
        self.var_interest  = tk.StringVar(value="-")
        self.var_total     = tk.StringVar(value="-")
        self.var_effective = tk.StringVar(value="-")

        stat_card(summary_section, "เงินต้น",                    self.var_principal, COLORS["text"])
        stat_card(summary_section, "ดอกเบี้ยรวม",                self.var_interest,  COLORS["accent2"])
        stat_card(summary_section, "ยอดสุดท้าย",                 self.var_total,     COLORS["accent"])
        stat_card(summary_section, "อัตราดอกเบี้ยแท้จริง (EAR)", self.var_effective, COLORS["danger"])

    def _build_main_panel(self, parent):
        panel = ctk.CTkFrame(parent, fg_color=COLORS["panel"], corner_radius=12)
        panel.pack(side="right", fill="both", expand=True)

        table_header = ctk.CTkFrame(panel, fg_color="transparent")
        table_header.pack(fill="x", padx=20, pady=(16, 8))
        ctk.CTkLabel(table_header, text="ตารางแสดงผลรายงวด",
                     font=FONT_HEAD, text_color=COLORS["text"]).pack(side="left")
        self.row_count_label = ctk.CTkLabel(table_header, text="",
                                             font=FONT_SMALL, text_color=COLORS["subtext"])
        self.row_count_label.pack(side="right")

        tree_frame = ctk.CTkFrame(panel, fg_color=COLORS["card"], corner_radius=8)
        tree_frame.pack(fill="both", expand=True, padx=16, pady=(0, 16))

        scroll_y = ttk.Scrollbar(tree_frame, orient="vertical")
        scroll_x = ttk.Scrollbar(tree_frame, orient="horizontal")

        self.tree = ttk.Treeview(
            tree_frame,
            columns=("งวด", "ยอดก่อนดอกเบี้ย", "ดอกเบี้ย", "ยอดสะสม"),
            show="headings",
            yscrollcommand=scroll_y.set,
            xscrollcommand=scroll_x.set,
            style="Finance.Treeview",
        )
        scroll_y.config(command=self.tree.yview)
        scroll_x.config(command=self.tree.xview)

        col_config = [
            ("งวด",              90,  "center"),
            ("ยอดก่อนดอกเบี้ย", 200, "e"),
            ("ดอกเบี้ย",        160, "e"),
            ("ยอดสะสม",         200, "e"),
        ]
        for col, width, anchor in col_config:
            self.tree.heading(col, text=col)
            self.tree.column(col, width=width, anchor=anchor, minwidth=60)

        scroll_y.pack(side="right", fill="y")
        scroll_x.pack(side="bottom", fill="x")
        self.tree.pack(fill="both", expand=True)

        self.tree.tag_configure("even",  background=COLORS["row_even"], foreground=COLORS["text"])
        self.tree.tag_configure("odd",   background=COLORS["row_odd"],  foreground=COLORS["text"])
        self.tree.tag_configure("total", background=COLORS["row_total"], foreground=COLORS["accent2"],
                                font=("Helvetica Neue", 12, "bold"))

    # ── Treeview Style ───────────────────────
    def _style_treeview(self):
        style = ttk.Style()
        style.theme_use("clam")
        style.configure("Finance.Treeview",
                        background=COLORS["row_odd"], foreground=COLORS["text"],
                        fieldbackground=COLORS["row_odd"], rowheight=32,
                        font=FONT_MONO, borderwidth=0)
        style.configure("Finance.Treeview.Heading",
                        background=COLORS["card"], foreground=COLORS["subtext"],
                        font=("Helvetica Neue", 11, "bold"),
                        relief="flat", borderwidth=0, padding=8)
        style.map("Finance.Treeview",
                  background=[("selected", COLORS["accent"])],
                  foreground=[("selected", "#ffffff")])
        style.map("Finance.Treeview.Heading",
                  background=[("active", COLORS["border"])])

    # ── Event Handlers ───────────────────────
    def _on_mode_change(self, mode_label: str):
        _, _, desc = MODES[mode_label]
        # ✅ ลบ ℹ️ ออก → variation selector U+FE0F อาจทำให้ Tcl crash
        self.mode_desc_var.set(desc)

    def _on_calculate(self):
        self.error_var.set("")
        try:
            principal = float(self.entry_principal.get())
            rate      = float(self.entry_rate.get()) / 100
            period    = int(self.entry_period.get())
            if principal <= 0 or rate <= 0 or period <= 0:
                raise ValueError("ค่าต้องมากกว่า 0")
        except ValueError as e:
            # ✅ ลบ ⚠ ออก → แม้จะอยู่ใน BMP แต่ป้องกันปัญหา font rendering บน Windows
            self.error_var.set(f"กรุณากรอกข้อมูลให้ถูกต้อง: {e}")
            return

        self._run_calculation(principal, rate, period, self.combo_mode.get())

    def _run_calculation(self, principal: float, rate: float, period: int, mode_label: str):
        for row in self.tree.get_children():
            self.tree.delete(row)

        n, unit_label, _ = MODES[mode_label]
        is_simple = (n == 0)

        if is_simple:
            period_rate = rate / 12
            ear = rate
        else:
            period_rate = rate / n
            ear = (1 + period_rate) ** n - 1

        balance        = principal
        total_interest = 0.0

        for i in range(1, period + 1):
            before   = balance
            interest = principal * period_rate if is_simple else balance * period_rate
            balance        += interest
            total_interest += interest

            tag = "even" if i % 2 == 0 else "odd"
            self.tree.insert("", "end", tags=(tag,), values=(
                f"{i:,}",
                f"{before:,.2f}",
                f"{interest:,.2f}",
                f"{balance:,.2f}",
            ))

        self.tree.insert("", "end", tags=("total",), values=(
            "รวม", "-", f"{total_interest:,.2f}", f"{balance:,.2f}",
        ))

        self.row_count_label.configure(text=f"{period:,} {unit_label}")
        self.var_principal.set(f"{principal:,.2f} B")
        self.var_interest.set(f"{total_interest:,.2f} B")
        self.var_total.set(f"{balance:,.2f} B")
        self.var_effective.set(f"{ear * 100:.4f} %")

    def _clear(self):
        for entry in (self.entry_principal, self.entry_rate, self.entry_period):
            entry.delete(0, "end")
        for row in self.tree.get_children():
            self.tree.delete(row)
        self.error_var.set("")
        self.row_count_label.configure(text="")
        self.var_principal.set("-")
        self.var_interest.set("-")
        self.var_total.set("-")
        self.var_effective.set("-")
        self.mode_desc_var.set("")


# ─────────────────────────────────────────────
if __name__ == "__main__":
    app = FinanceApp()
    app.mainloop()
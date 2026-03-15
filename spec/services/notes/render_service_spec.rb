require "rails_helper"

RSpec.describe Notes::RenderService do
  def render(markdown)
    described_class.call(markdown)
  end

  describe ".call" do
    it "renders basic markdown to HTML" do
      html = render("# Título\n\nParágrafo simples.")
      expect(html).to include("<h1>")
      expect(html).to include("Título")
      expect(html).to include("<p>Parágrafo simples.</p>")
    end

    it "renders bold and italic" do
      html = render("**negrito** e _itálico_")
      expect(html).to include("<strong>negrito</strong>")
      expect(html).to include("<em>itálico</em>")
    end

    it "renders inline code" do
      html = render("`código`")
      expect(html).to include("<code>código</code>")
    end

    it "renders code blocks" do
      html = render("```ruby\nputs 'hello'\n```")
      expect(html).to include("<pre>")
      expect(html).to include("<code")
    end

    it "renders links" do
      html = render("[texto](https://example.com)")
      expect(html).to include('href="https://example.com"')
      expect(html).to include("texto")
    end

    it "renders unordered lists" do
      html = render("- item 1\n- item 2")
      expect(html).to include("<ul>")
      expect(html).to include("<li>item 1</li>")
    end

    it "renders ordered lists" do
      html = render("1. primeiro\n2. segundo")
      expect(html).to include("<ol>")
    end

    it "renders blockquotes" do
      html = render("> citação importante")
      expect(html).to include("<blockquote>")
    end

    it "renders tables" do
      md = "| col1 | col2 |\n|------|------|\n| a    | b    |"
      html = render(md)
      expect(html).to include("<table>")
      expect(html).to include("<th>col1</th>")
    end

    describe "sanitization" do
      it "strips script tags" do
        html = render("<script>alert('xss')</script>")
        expect(html).not_to include("<script>")
        expect(html).not_to include("alert(")
      end

      it "strips onclick handlers" do
        html = render("[click](javascript:alert(1))")
        expect(html).not_to include("javascript:")
      end

      it "strips style attributes" do
        html = render('<p style="color:red">text</p>')
        expect(html).not_to include('style="color:red"')
      end

      it "allows safe href attributes" do
        html = render("[link](https://safe.com)")
        expect(html).to include('href="https://safe.com"')
      end
    end

    describe "CJK text" do
      it "renders Mandarin text correctly" do
        html = render("# 标题\n\n这是一段中文内容。")
        expect(html).to include("标题")
        expect(html).to include("这是一段中文内容")
      end

      it "renders Japanese text correctly" do
        html = render("## 日本語のタイトル\n\nひらがなとカタカナ。")
        expect(html).to include("日本語のタイトル")
        expect(html).to include("ひらがな")
      end

      it "renders Korean text correctly" do
        html = render("### 한국어 제목\n\n안녕하세요.")
        expect(html).to include("한국어 제목")
        expect(html).to include("안녕하세요")
      end
    end

    it "handles empty string" do
      html = render("")
      expect(html).to be_a(String)
    end

    it "handles nil gracefully" do
      html = render(nil)
      expect(html).to be_a(String)
    end

    # Bug fix: wiki-link syntax [[Display|uuid]] must be resolved to <a> tags,
    # not passed through as raw text. These tests document the expected behaviour.
    describe "wiki-link rendering" do
      let!(:target) { create(:note, title: "Nota Destino") }

      it "renders [[Display|uuid]] as an anchor tag for valid note" do
        html = render("Veja [[Nota Destino|#{target.id}]] para mais.")
        expect(html).to include("<a ")
        expect(html).to include("Nota Destino")
        expect(html).not_to include("[[")
        expect(html).not_to include("]]")
      end

      it "does not show raw [[...]] syntax in output" do
        html = render("Veja [[Minha Nota|#{target.id}]].")
        expect(html).not_to match(/\[\[.*\]\]/)
      end

      it "renders broken wiki-link (invalid UUID) as wikilink-broken span" do
        bad_uuid = "00000000-0000-0000-0000-000000000000"
        html = render("Veja [[Link Quebrado|#{bad_uuid}]].")
        expect(html).to include("wikilink-broken")
        expect(html).to include("Link Quebrado")
        expect(html).not_to include("[[")
      end

      it "renders non-uuid wiki-link target as wikilink-broken span" do
        html = render("Veja [[Link Quebrado|nao-e-uuid]].")
        expect(html).to include("wikilink-broken")
        expect(html).to include("Link Quebrado")
        expect(html).not_to include("[[")
      end

      it "renders [[Display|f:uuid]] with hier_role prefix" do
        html = render("Parent: [[Nota Pai|f:#{target.id}]]")
        expect(html).to include("<a ")
        expect(html).to include("Nota Pai")
        expect(html).not_to include("[[")
      end

      it "renders [[Display|c:uuid]] with child role prefix" do
        html = render("Child: [[Nota Filha|c:#{target.id}]]")
        expect(html).to include("<a ")
        expect(html).to include("Nota Filha")
        expect(html).not_to include("[[")
      end

      it "preserves display text separate from note title" do
        html = render("Veja [[Texto Livre|#{target.id}]] aqui.")
        expect(html).to include("Texto Livre")
        # title attribute shows real note title when display differs
        expect(html).to include('title="Nota Destino"')
      end

      it "uses display text when it matches note title (no redundant title attr)" do
        html = render("Veja [[Nota Destino|#{target.id}]] aqui.")
        # When display == title, no extra title attribute is added
        expect(html).not_to include('title=')
      end
    end
  end
end

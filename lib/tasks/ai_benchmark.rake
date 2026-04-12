# frozen_string_literal: true

namespace :ai do
  desc "Benchmark AI models across all configured Ollama hosts"
  task benchmark: :environment do
    require_relative "../../app/services/ai/ollama_provider"
    require_relative "../../app/services/ai/prompt_builder"

    $stdout.sync = true

    ALL_CAPABILITIES = %w[grammar_review rewrite seed_note translate import_analyze].freeze
    CAPABILITIES = if ENV["CAPABILITY"].present?
      ENV["CAPABILITY"].split(",").map(&:strip) & ALL_CAPABILITIES
    else
      ALL_CAPABILITIES
    end

    SAMPLES = {
      short: {
        label: "Curto (~400 chars)",
        text: <<~TEXT
          A inteligencia artificial tem avansado rapodamente nos ultimos anos.
          Modelos de linguagem naturais conseguem agora entender e gerar textos
          com uma qualidade que era impensavel a poucos anos atras. Essa evolusao
          traz desafios eticos e praticos para a sociedade, como a necessidade de
          regulamentar o uso dessas tecnologias e garantir que elas sejam usadas
          de forma responsavel e benéfica para todos.
        TEXT
      },
      medium: {
        label: "Medio (~1200 chars)",
        text: <<~TEXT
          ## Arquitetura de Microsservicos

          A arquitetura de microsservicos é um estilo de desenvolvimento que estrutura
          uma aplicacao como um conjunto de servicos pequenos e independentes. Cada
          servico executa em seu proprio processo e se comunica com mecanismos leves,
          geralmente uma API de recursos HTTP.

          ### Vantagems

          - **Escalabilidade independente**: Cada servico pode ser escalado separadamente
          - **Resiliencia**: A falha de um servico nao derruba os outros
          - **Flexibilidade tecnologica**: Cada equipe pode escolher a melhor ferramenta
          - **Deploy independente**: Atualizacoes pontuais sem redeploy completo

          ### Desvantajens

          - Complexidade operacional: mais servicos = mais infraestrutura
          - Comunicacao entre servicos: latencia de rede e falhas parciais
          - Consistencia eventual: transacoes distribuidas sao dificeis
          - Monitoramento: rastrear problemas atraves de multiplos servicos

          A decisao entre monolito e microsservicos depende do tamanho da equipe,
          da complexidade do dominio e da maturidade da infraestrutura.
        TEXT
      },
      long: {
        label: "Longo (~3000 chars)",
        text: <<~TEXT
          ## Capitulo 1: Fundamentos de Redes Neurais

          As redes neurais artificials sao modelos computacionais inspirados na
          estrutura e funcionamento do cerebro humano. Compostas por camadas de
          neuronios interconectados, essas redes aprendem a reconhecer padroes
          complexos nos dados atraves de um processo iterativo de treinamento.

          ### 1.1 O Neuronio Artificial

          O neuronio artificial, ou perceptron, é a unidade basica de uma rede neural.
          Ele recebe multiplas entradas, cada uma multiplicada por um peso, soma esses
          valores ponderados, adiciona um vies (bias), e aplica uma funcao de ativacao
          para produzir a saida.

          A funcao de ativacao determina se o neuronio deve ser "ativado" ou nao,
          introduzindo nao-linearidade no modelo. Funcoes comuns incluem:

          - **Sigmoid**: Mapeia valores para o intervalo (0, 1)
          - **ReLU**: Retorna zero para valores negativos e o proprio valor para positivos
          - **Tanh**: Mapeia valores para o intervalo (-1, 1)
          - **Softmax**: Converte um vetor de valores em uma distribuicao de probabilidade

          ### 1.2 Arquitetura de Camadas

          Uma rede neural tipica consiste em tres tipos de camadas:

          1. **Camada de entrada**: Recebe os dados brutos (pixels, caracteres, numeros)
          2. **Camadas ocultas**: Processam e transformam os dados intermediarios
          3. **Camada de saida**: Produz o resultado final (classificacao, regressao)

          O numero de camadas ocultas e neuronios em cada camada sao hiperparametros
          que devem ser ajustados durante o desenvolvimento do modelo. Redes com muitas
          camadas ocultas sao chamadas de "redes profundas" (deep networks).

          ### 1.3 Treinamento e Retropropagacao

          O treinamento de uma rede neural envolve:

          1. **Propagacao direta**: Os dados fluem da entrada para a saida
          2. **Calculo do erro**: A diferenca entre a saida prevista e a esperada
          3. **Retropropagacao**: O erro é propagado de volta para ajustar os pesos
          4. **Atualizacao dos pesos**: Usando um otimizador (SGD, Adam, RMSprop)

          Este ciclo se repete por muitas epocas ate que o modelo atinja um nivel
          aceitavel de precisao nos dados de validacao.

          ### 1.4 Overfitting e Regularizacao

          Quando um modelo se ajusta demais aos dados de treinamento, perdendo a
          capacidade de generalizar para dados novos, dizemos que ocorreu overfitting.
          Tecnicas de regularizacao incluem:

          - **Dropout**: Desativa aleatoriamente neuronios durante o treinamento
          - **L1/L2 regularization**: Penaliza pesos grandes na funcao de custo
          - **Early stopping**: Interrompe o treinamento quando a validacao degrada
          - **Data augmentation**: Aumenta artificialmente o dataset de treinamento
        TEXT
      }
    }.freeze

    TRANSLATE_OPTS = { language: "pt", target_language: "en" }.freeze

    IMPORT_ANALYZE_SAMPLE = <<~MD
      # Sumário

      1. Introdução às Redes Neurais
      2. Arquitetura de Camadas
      3. Treinamento e Retropropagação
      4. Aplicações Práticas

      ---

      # 1. Introdução às Redes Neurais

      As redes neurais artificiais são modelos computacionais inspirados na estrutura
      e funcionamento do cérebro humano. Compostas por camadas de neurônios
      interconectados, essas redes aprendem a reconhecer padrões complexos nos dados
      através de um processo iterativo de treinamento.

      O conceito surgiu na década de 1940, mas só se tornou prático com o aumento
      do poder computacional nas últimas décadas. Hoje, redes neurais são usadas
      em reconhecimento de imagem, processamento de linguagem natural, diagnóstico
      médico e muitas outras áreas.

      # 2. Arquitetura de Camadas

      Uma rede neural típica consiste em três tipos de camadas:

      - **Camada de entrada**: Recebe os dados brutos
      - **Camadas ocultas**: Processam e transformam os dados
      - **Camada de saída**: Produz o resultado final

      O número de camadas ocultas define a "profundidade" da rede.
      Redes profundas (deep learning) podem ter centenas de camadas.

      ## Funções de Ativação

      As funções de ativação introduzem não-linearidade:
      - Sigmoid: (0, 1)
      - ReLU: max(0, x)
      - Tanh: (-1, 1)

      # 3. Treinamento e Retropropagação

      O treinamento segue um ciclo:

      1. Propagação direta dos dados
      2. Cálculo do erro (loss function)
      3. Retropropagação do erro
      4. Atualização dos pesos via otimizador

      Este ciclo se repete por muitas épocas. Técnicas como dropout e
      regularização L2 previnem overfitting.

      # 4. Aplicações Práticas

      - Visão computacional (classificação de imagens, detecção de objetos)
      - NLP (tradução, chatbots, análise de sentimento)
      - Sistemas de recomendação
      - Veículos autônomos
      - Diagnóstico médico por imagem
    MD

    hosts = discover_ollama_hosts
    if hosts.empty?
      puts "Nenhum host Ollama configurado ou acessivel."
      exit 1
    end

    puts "=" * 90
    puts "AI Benchmark — #{Time.current.strftime("%Y-%m-%d %H:%M")}"
    puts "=" * 90
    puts

    hosts.each do |host|
      puts "Host: #{host[:name]} (#{host[:base_url]})"
      puts "Modelos disponiveis: #{host[:models].join(", ")}"
      puts
    end

    results = []

    CAPABILITIES.each do |capability|
      puts "-" * 90
      puts "Capability: #{capability}"
      puts "-" * 90

      samples = if capability == "import_analyze"
        { import: { label: "Documento markdown (~60 linhas)", text: IMPORT_ANALYZE_SAMPLE } }
      else
        SAMPLES
      end

      samples.each do |size_key, sample|
        puts "\n  #{sample[:label]} (#{sample[:text].length} chars):"

        hosts.each do |host|
          host[:models].each do |model_name|
            result = run_benchmark(
              host: host,
              model: model_name,
              capability: capability,
              text: sample[:text],
              size: size_key
            )
            results << result
            print_result(result)
          end
        end
      end
    end

    puts "\n#{"=" * 90}"
    puts "RESUMO"
    puts "=" * 90
    print_summary(results)
  end
end

def discover_ollama_hosts
  hosts = []
  provider_names = ENV.fetch("AI_ENABLED_PROVIDERS", "ollama").split(",").map(&:strip)
  ollama_names = provider_names.select { |n| n.start_with?("ollama") }

  ollama_names.each do |name|
    config = Ai::ProviderRegistry.send(:provider_config, name)
    next unless config[:base_url].present?

    begin
      models = Ai::OllamaProvider.available_models(base_url: config[:base_url])
      hosts << { name: name, base_url: config[:base_url], models: models }
    rescue => e
      puts "AVISO: #{name} (#{config[:base_url]}) inacessivel: #{e.message}"
    end
  end

  hosts
end

def run_benchmark(host:, model:, capability:, text:, size:)
  provider = Ai::OllamaProvider.new(
    name: host[:name], model: model, base_url: host[:base_url]
  )

  extra = capability == "translate" ? TRANSLATE_OPTS : {}
  prompt_text = capability == "seed_note" ? "Redes Neurais Artificiais" : text

  start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = provider.review(capability: capability, text: prompt_text, language: extra[:language] || "pt", target_language: extra[:target_language])
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

  {
    host: host[:name], model: model, capability: capability, size: size,
    elapsed: elapsed.round(2),
    tokens_in: result.tokens_in, tokens_out: result.tokens_out,
    output_length: result.content.to_s.length,
    output_preview: result.content.to_s.lines.first(3).join.strip.truncate(120),
    status: :ok
  }
rescue => e
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - (start_time || Process.clock_gettime(Process::CLOCK_MONOTONIC))
  {
    host: host[:name], model: model, capability: capability, size: size,
    elapsed: elapsed.round(2),
    tokens_in: 0, tokens_out: 0, output_length: 0,
    output_preview: "ERRO: #{e.message.truncate(80)}",
    status: :error
  }
end

def print_result(r)
  status_icon = r[:status] == :ok ? "OK" : "FAIL"
  printf "    %-20s %-18s %6.1fs  tok_in:%-5d tok_out:%-5d out:%d chars [%s]\n",
    "#{r[:host]}/#{r[:model]}", status_icon,
    r[:elapsed], r[:tokens_in], r[:tokens_out], r[:output_length],
    r[:output_preview].truncate(60)
end

def print_summary(results)
  by_host_model = results.select { |r| r[:status] == :ok }.group_by { |r| "#{r[:host]}/#{r[:model]}" }

  by_host_model.each do |key, runs|
    avg_time = (runs.sum { |r| r[:elapsed] } / runs.size).round(2)
    total_tokens = runs.sum { |r| r[:tokens_out] }
    success_rate = "#{runs.size}/#{results.count { |r| "#{r[:host]}/#{r[:model]}" == key }}"

    printf "  %-35s avg:%.1fs  total_tok_out:%-6d  success:%s\n",
      key, avg_time, total_tokens, success_rate
  end
end

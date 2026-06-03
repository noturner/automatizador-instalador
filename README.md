# Instalador 

Esta versão cuida de toda a configuração do ambiente de recuperação e da instalação do AVELL One Control, **sem instalar nenhum SDK ou driver adicional**.

---

## O que o instalador faz

- Cria e configura automaticamente a **partição de recuperação (R:)**
- Aplica a imagem de recuperação **AVELL WinPE** (`winpe.wim`)
- Configura o **Windows Boot Manager** com a entrada de recuperação:
  - Descrição: `Recuperar-Windows-Avell`
  - Uso de GUID da partição para maior robustez
- Instala o **aplicativo puro** em modo silencioso (até 5 tentativas)
- Reinicia o sistema automaticamente ao final

---

## Requisitos

- Windows 10 ou 11
- Execução como **Administrador**
- Pelo menos **35 GB livres** na unidade C:
- SDK/hardware já instalado e funcional (RGB, fans etc.)
- Todos os arquivos na **mesma pasta**:
  - `instalador.exe`
  - `caller.bat`
  - `install.ps1`
  - `OC56.exe`
  - `winpe.wim`
  - `logo.png`, `logo.ico`, `Leia-me.txt` (opcional, mas recomendado)

---

## Como usar

1. Copie a pasta completa do instalador para a máquina de destino.
2. Clique com o botão direito em `instalador.exe` → **Executar como administrador**.
3. Clique em **Instalar** e aguarde:
   - O processo pode levar de 10 a 30 minutos, dependendo do disco.
4. Ao final, o sistema será reiniciado automaticamente.

---

## Logs e diagnóstico

Após a execução, são gerados dois arquivos de log na mesma pasta:

- `install.log`  
  Log detalhado do script PowerShell (etapa a etapa).

- `install_debug.txt`  
  Saída completa capturada pela interface gráfica (stdout), útil para sincronismo de progresso e diagnóstico.

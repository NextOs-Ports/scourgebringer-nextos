# HANDOFF — ScourgeBringer (MonoGame/.NET Android), framework 6.8

**Estado (2026-08-13): baseline NextOS/Mali-450 jogável preservado; o ZIP exato
`1.0.0-test.5` passou no DarkOS a árvore/próximo nível, morte/retorno, gameplay
e save; o ELF exato `1.0.0-test.8` passou fisicamente o menu inicial e movimento
completo de gameplay em glibc 2.41, mas ainda não tem prova física em glibc
2.30.** A `test.4`
corrigiu os imports ausentes na glibc 2.30 e a `test.5` forneceu o grafo offline
exato `ReviewManager` → `Task`, eliminando a tela preta tardia sem pular
`ToNextLevel()`.

O log posterior do ArkOS4Clone mostrou o próximo muro depois de `Runtime_init`.
O endereço de falha `0x15250` é o PLT0 de `libSystem.Native.so`: nessa glibc,
`arc4random_buf` e `mknod` não são exports dinâmicos, e o construtor de
`System.Random` salta pelo slot não resolvido durante `MainActivity.n_onCreate`.
A `test.7` fornece os dois símbolos explicitamente; `arc4random_buf` usa
`getrandom(2)` com fallback `/dev/urandom`, seguindo o port aprovado de Stardew
Valley. Ela também preserva a correção anterior do Mono, que traduz
`sigemptyset`, `sigfillset`, `sigaddset`, `sigdelset`, `sigismember`,
`sigprocmask`, `pthread_sigmask`, `sigsuspend` e `sigpending`, além de
`sigaction`. O reporter usa altstack, buffer fixo, `write(2)` e `_exit(2)`.
Não declarar ArkOS/ArkOS4Clone aprovado até o ZIP e SHA-256 exatos passarem
fisicamente num aparelho com glibc 2.30.

A `test.8` corrige a entrada Discord invisível que ainda existia na lógica do
menu inicial Android. A primeira tentativa de neutralizar o eixo horizontal
foi rejeitada na validação porque o `TitleScreenManager` conserva `MainMenu`
durante a partida e isso removia movimento lateral. A correção final não filtra
entrada: depois do update nativo, se `_selectedMenuItem` for somente o Discord
não desenhado, ela restaura a última opção visível. O ELF exato
`a245edea4cf83dd9f1dc0e9b808ddf6e9d15ecaee35433bba8bc78c2555c0273`
passou menu, Configurações e movimento de gameplay nas duas direções; o usuário
confirmou visualmente o resultado.

O candidato comunitário `scourgebringer.zip` da `1.0.0-test.8` foi gerado
depois dessa prova, com SHA-256
`418a8681c91f83fd77e717762b91eb09c1df0400aea0140228a4075d5e4c160d`.
O `nxrelease verify` conferiu os 24 arquivos, os dois ELFs e teto real
`GLIBC_2.17`; a auditoria desempacotada confirmou o `INSTALLATION.md` exato,
nenhum APK/save/log, nenhum caminho privado e nenhum comando externo `stat`.
O launcher empacotado também passou a falha pré-runtime com status 1 verdadeiro,
um único log `0600` e uma única finalização PortMaster.

- **APKs de origem validados:** 1.61.16 (store clássico) e 1.61 b19
  (`libassemblies.arm64-v8a.blob.so`), ambos `com.pid.scourgebringer` AArch64.
- **Compatibilidade flexível:** b17, b18 e outras 1.61.x podem passar sem
  whitelist de versão quando preservam pacote, ABI, conteúdo central, 12 idiomas
  e bibliotecas exigidas; somente 1.61.16 e b19 têm prova exata nesta sessão.
- **Engine:** MonoGame 3.8.1.303 + .NET-for-Android / MonoVM. **arm64-v8a apenas.**
- **Arquitetura:** so-loader, terceiro da linhagem Mono-Android do repo
  (`stardewvalley` → `tmntsr` → este), clonando o `ports/tmntsr`.
- **Framework:** branch `framework/nxbootstrap-0.6.8`, commit
  `583ec1e977eb377669414fe949969bd784ced730`; versões e hash do ELF em
  `FRAMEWORK-PIN.json`. O `build.sh` extrai esse commit por `git archive`,
  confere as 12 versões fixadas e monta apenas o snapshot read-only no builder;
  o checkout móvel do framework nunca entra nos bytes de release.

## Evidência física

| Item | Medição |
|---|---|
| Vídeo | baseline NextOS 1280×720; prova ArkOS 640×480, pixel art íntegra |
| Aspecto ArkOS 6.8 | `requested=640x480 drawable=640x480 aspect=4:3`; `source=0,60 640x360 mode=stretch-to-fill`; sem barras confirmado visualmente |
| Ritmo | 40,00 fps cravados, `late=0/300`, 7 mil swaps sem queda |
| Memória | RSS ~117 MiB, **swap 0**, ~455 MiB disponíveis |
| Áudio | picos de 1000–4200 (de 32767) por janela de ~4 s durante o jogo |
| Controle | `Found new controller [0]` do MonoGame; andar e atacar conferidos na tela; **`L2`/`R2` corrigidos e aprovados em 23/jul**; test.8 entregou analógico completo de `-32768` a `32767` no gameplay, sem filtro |
| Idioma | 12 perfis; `pt-br` → `pt-BR`/`PB` confirmado por captura em português e `Language=PB` persistente |
| Save | `data/.config/.isolated-storage/`; legado copiado uma vez, origem e destino com hash idêntico após os dois APKs |
| Saída | Quit/B chamou `finishAndRemoveTask`, seguiu `onPause` → `onStop` → `onDestroy` e terminou com status 0 |
| Launcher entregue | `ports_scripts/ScourgeBringer.sh` levado até o gameplay, processo encerrado e ES ativo de novo (`screenshots/03-launcher-portmaster.png`) |
| DarkOS `test.4` | ZIP exato instalado, ELF `6ded1a…` confirmado, framework READY 9/9, save local de reprodução carregado e gameplay ativo; entrada na árvore reproduziu `RequestReview()` → `NullReferenceException` antes de `ToNextLevel()` concluir |
| DarkOS `test.5` | ZIP exato SHA-256 `f24209d7…` confirmado pelo usuário: árvore/próximo nível, morte/retorno, gameplay e save sem tela preta |
| `test.7` em glibc 2.41 | ELF exato `430e40ee…`; duas aberturas KMSDRM passaram `MainActivity.n_onCreate`, FMOD/ALSA, controle, READY 9/9 e primeiro swap; ambas encerraram status 0; segunda abertura aceitou o fast marker com zero reextração |
| `test.8` em glibc 2.41 | ELF exato `a245edea…`; esquerda/direita restauraram a última seleção visível do menu raiz, baixo selecionou Configurações, direita continuou ativa dentro dela e o analógico completo moveu o personagem nas duas direções; confirmado visualmente pelo usuário |

## Layout no aparelho

```text
<raiz-rom>/ports/
├── ScourgeBringer.sh
└── scourgebringer/
    ├── scourgebringer-nextos
    ├── nxport.json
    ├── extractor.json
    ├── port-env.sh
    ├── nxextract/
    ├── gamedata/<fonte-legal>.apk
    ├── assemblies.apk       # gerado pelo NXExtract
    ├── assets/Content/       # gerado pelo NXExtract
    ├── runtime-libs/        # gerado e selado pelo NXExtract, sem libaot-*
    └── data/.config/.isolated-storage/
```

O launcher gerado cuida de PortMaster, lock único, extração, gates de arquivos,
log, sinais e devolução do frontend. Diagnósticos podem usar `SB_JNI_VERBOSE=1`,
`SB_INPUT_TRACE=1`, `SB_TITLE_TRACE=1`, `SB_AUDIO_TRACE=1` e `SB_GL_TRACE=1`; o último continua
restrito a execuções curtas no Mali-450.

## Muros derrubados (para quem for portar o próximo Mono-Android)

1. **Dois formatos de assembly store.** O 1.61.16 usa
   `assemblies/assemblies.blob`; o b19 usa
   `libassemblies.arm64-v8a.blob.so`. O wrapper `Runtime_init` de ambos foi
   conferido no disassembly. A receita detecta o formato e passa um APK
   reduzido por `runtimeApks`, com entradas `STORED` e alinhadas.
2. **`DT_NEEDED`.** O loader agora mapeia as dependências antes do módulo e
   acumula os símbolos numa tabela global.
3. **`JNI_OnLoad` dos módulos dinâmicos.** No Android quem chama é o
   `System.loadLibrary`. O `libfmod.so` depende disso para guardar a `JavaVM`.
4. **`pthread_attr_t`: 56 B no bionic, 64 B na glibc/aarch64.** O
   `pthread_attr_init` da glibc escrevia 8 bytes além do storage do chamador e
   apagava um registrador salvo na pilha; o FMOD voltava com `x24 = 0` e morria
   num `ldr`. Está implementado o layout bionic inteiro em `pthread_bridge.c`.
   **Esse bug existe em qualquer port so-loader; vale conferir nos outros.**
5. **`pthread_attr_setstacksize`.** O bionic aceita pilhas menores que o
   `PTHREAD_STACK_MIN` da glibc; devolver `EINVAL` fazia `System::init` do FMOD
   responder ERR_INTERNAL.
6. **Nomes linkáveis não são necessariamente exports dinâmicos.** Em AArch64,
   a glibc até 2.32 resolve `stat`/`lstat`/`fstat`/`fstatat` via
   `libc_nonshared.a`, mas `dlsym(RTLD_DEFAULT, "stat")` devolve `NULL`. O gate
   de um port Bionic precisa inventariar todos os `UND` dos guests e registrar
   aliases fortes ausentes no adapter; aviso `UNRESOLVED` não é aceitável. A
   `test.4` também cobre `strlcpy` e o símbolo de dados `_ctype_`, com regressão
   em `tests/test_bionic_compat.c`.
7. **`libaaudio.so` virtual sobre SDL2** (`src/aaudio_shim.c`): é por ela que o
   FMOD abre áudio no Android. Só 23 símbolos, todos listados no `.so`.
   `org.fmod.FMOD.supportsAAudio` responde sim no shim JNI.
8. **`dlclose` na tabela de shims.** O FMOD fecha o handle virtual no teardown e
   isso caía dentro do `ld-linux`.
9. **Banks do FMOD** chegam como `file:///android_asset/...`.
10. **Política de textura do TMNT desligada por padrão** (downscale, RGBA4444,
   ETC1, ASTC). Aqui toda textura é `SurfaceFormat.Color` e o jogo é pixel art:
   com a política ligada a tela ficava preta.
11. **Lista de métodos do ACW.** O `crc645d6a1e7bece73b70.Program` declara
    exatamente sete métodos nativos. Um a mais e o `TypeManager` não acha o
    getter do handler e **derruba o registro inteiro** — foi assim que o
    `n_onActivityResult` ficou sem handler. Tire a lista do dex, sempre.
12. **Google Play Games.** O jogo só libera o título quando o helper chega a
    `NotConnected`. A Task de `silentSignIn` não completa aqui (o listener é um
    ACW genérico que nenhuma JVM instancia), mas o jogo tem o mesmo destino pelo
    evento de login cancelado: `onActivityResult(0x2329, RESULT_CANCELED)` →
    `ProcessSignIn()` → conta nula → `FinishLoading(NotConnected)`, que ainda
    carrega os saves locais. O shim entrega esse evento **na thread do game
    loop** (entregar da thread de input estourava `IO_SharingViolation` no
    IsolatedStorage) e **só a partir da terceira consulta de conta** (antes
    disso o `SignInSilently` sobrescreve o estado logo em seguida).
13. **Google Play Core Review aparece tarde.** O helper de review não roda no
    boot; `GameStates.ToNextLevel()` o chama ao entrar na árvore. O método
    gerenciado guarda a resposta de `ReviewManagerFactory.Create()` e chama
    `RequestReviewFlow()` sem conferir `null`. Uma resposta JNI genérica nula
    passa por minutos de gameplay e só então destrói o loop com NRE. O adapter
    fornece peers não nulos somente para as classes exatas
    `com.google.android.play.core.review.ReviewManagerFactory`,
    `ReviewManager` e `com.google.android.play.core.tasks.Task`; a avaliação é
    um no-op offline e a transição continua pertencendo ao jogo. O gate
    `tests/test_play_review_contract.py` impede voltar a um fallback global de
    qualquer método chamado `create`.
14. **Persistência fora do selo.** O Java original passa `filesDir`, `cacheDir`
    e `nativeLibraryDir` nessa ordem. Reproduzir os três moveu IsolatedStorage
    para `data`, impedindo que um save altere `runtime-libs` e force extração.
15. **Saída nativa.** O shim reconhece `finish`, `finishAffinity` e
    `finishAndRemoveTask`; o loop externo observa o pedido e completa o
    lifecycle Android em vez de manter uma janela preta.
16. **Idioma.** `NXPORT_LANGUAGE` é traduzido para locale do runtime, language
    e country Android e os 12 códigos reais de `Content/Localizations`.
17. **`sigset_t` também é ABI, não apenas `sigaction`.** No Bionic arm64 a
    máscara tem 8 bytes; na glibc AArch64 ela tem 128. Traduzir só a struct de
    32 bytes deixa `sigemptyset`/`sigfillset` e máscaras de processo/thread
    corromperem até 120 bytes adjacentes durante o boot do Mono. O gate agora
    usa canários antes/depois do storage guest, cobre o bit 64, restauração de
    máscara e roda também em AArch64 emulado. Reporter fatal nunca deve usar
    stdio, `dladdr`, `/proc/self/maps` nem percorrer cegamente uma pilha já
    danificada.
18. **Estado do título persiste no gameplay.** `TitleScreenManager._state`
    continua `MainMenu` mesmo quando a tela de título já saiu; por isso ele não
    pode decidir se um eixo deve ser bloqueado. A correção segura deixa todos os
    eventos Android intactos e altera somente `_selectedMenuItem` quando o
    valor é `Discord`, entrada mantida pela lógica mas omitida pelo desenho. O
    último índice visível é restaurado na thread do game loop.

## Limites conhecidos

- O nome do APK não garante compatibilidade; pacote, ABI, conteúdo, 12 idiomas
  e bibliotecas precisam cumprir os limites da receita 1.61.x.
- **40 fps** é o `FramerateMode=Vsync` do próprio jogo; a tela de opções oferece
  outros modos. Vale medir 60 antes de mudar qualquer coisa.
- **PairIP** nunca apareceu: o dex não roda no so-loader, como previsto.
- A `test.8` passou boot/render/áudio/input, menu raiz, Configurações e movimento
  completo de gameplay em glibc 2.41; transição da árvore, morte/retorno e save
  prolongado continuam herdados da prova exata da `test.5`.
- O alvo autorizado nesta sessão informa glibc 2.41, embora use login `ark`.
  Ele serve como regressão, mas não prova o conserto específico da glibc 2.30.

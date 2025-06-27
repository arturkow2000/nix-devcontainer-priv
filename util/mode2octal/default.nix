{
  stdenv,
  autoreconfHook,
  gnulib,
  ...
}:
stdenv.mkDerivation {
  name = "mode2octal";
  src = ./.;
  nativeBuildInputs = [ autoreconfHook ];
  buildInputs = [ gnulib ];

  preAutoreconf = ''
    ${gnulib}/gnulib-tool.sh --lib=libgnu --source-base=lib --m4-base=gnulib-m4 \
      --tests-base=tests --with-tests \
      --import modechange
  '';

  meta.mainProgram = "mode2octal";
}

{
  dlib,
  lib,
}:
let
  l = lib // builtins;

  # INTERNAL

  subsystems = dlib.dirNames ./.;

  translatorTypes = [ "impure" "ifd" "pure" ];

  # attrset of: subsystem -> translator-type -> (function subsystem translator-type)
  mkTranslatorsSet = function:
    l.genAttrs (dlib.dirNames ./.) (subsystem:
      l.genAttrs
        (l.filter (dir: builtins.pathExists (./. + "/${subsystem}/${dir}")) translatorTypes)
        (transType: function subsystem transType)
    );

  # flat list of all translators sorted by priority (pure translators first)
  translatorsList =
    let
      list = l.collect (v: v ? subsystem) translators;
      prio = translator:
        if translator.type == "pure" then
          0
        else if translator.type == "ifd" then
          1
        else if translator.type == "impure" then
          2
        else
          3;
    in
      l.sort
        (a: b: (prio a) < (prio b))
        list;

  callTranslator = subsystem: type: name: file: args:
    let
      translatorModule = import file {
        inherit dlib lib;
      };

    in
      translatorModule // {
        inherit name subsystem type;
      };


  # EXPORTED

  # attrset of: subsystem -> translator-type -> translator
  translators = mkTranslatorsSet (subsystem: type:
    l.genAttrs (dlib.dirNames (./. + "/${subsystem}/${type}")) (translatorName:
      callTranslator subsystem type translatorName (./. + "/${subsystem}/${type}/${translatorName}") {}
    )
  );

  mapTranslators = f:
    l.mapAttrs
      (subsystem: types:
        l.mapAttrs
          (type: names:
            l.mapAttrs
              (name: translator: f translator)
              names)
          types)
      translators;

  # returns the list of translators including their special args
  # and adds a flag `compatible` to each translator indicating
  # if the translator is compatible to all given paths
  translatorsForInput =
    {
      source,
    }:
    l.forEach translatorsList
      (t: rec {
        inherit (t)
          name
          extraArgs
          subsystem
          type
        ;
        compatible = t.compatible { inherit source; };
      });

  # also includes subdirectories of the given paths up to a certain depth
  # to check for translator compatibility
  translatorsForInputRecursive =
    {
      source,
      depth ? 2,
    }:
    let
      listDirsRec = dir: depth:
        let
          subDirs =
            l.map
              (subdir: "${dir}/${subdir}")
              (dlib.listDirs dir);
        in
          if depth == 0 then
            subDirs
          else
            subDirs
            ++
            (l.flatten
              (map
                (subDir: listDirsRec subDir (depth -1))
                subDirs));

      dirsToCheck =
        [ source ]
        ++
        (l.flatten
          (map
            (inputDir: listDirsRec inputDir depth)
            [ source ]));

    in
      l.genAttrs
        dirsToCheck
        (dir:
          translatorsForInput {
            source = dir;
          }
        );


  # pupulates a translators special args with defaults
  getextraArgsDefaults = extraArgsDef:
    l.mapAttrs
      (name: def:
        if def.type == "flag" then
          false
        else
          def.default or null
      )
      extraArgsDef;


  # return one compatible translator or throw error
  findOneTranslator =
    {
      source,
      translatorName ? null,
    }@args:
    let
      translatorsForSource = translatorsForInput {
        inherit source;
      };

      nameFilter =
        if translatorName != null then
          (translator: translator.name == translatorName)
        else
          (translator: true);

      compatibleTranslators =
        let
          result =
            l.filter
              (t: t.compatible)
              translatorsForSource;
        in
          if result == [] then
            throw "Could not find a compatible translator for input"
          else
            result;

      translator =
        l.findFirst
          nameFilter
          (throw ''Specified translator ${translatorName} not found or incompatible'')
          compatibleTranslators;

    in
      translator;

in
{
  inherit
    findOneTranslator
    getextraArgsDefaults
    mapTranslators
    translators
    translatorsForInput
    translatorsForInputRecursive
  ;
}

use anyhow::{bail, Context, Result};
use nu_parser::parse;
use nu_protocol::{
    ast::{Block, Expr, Pipeline, PipelineElement},
    engine::{EngineState, StateWorkingSet},
    Span, Value,
};
use nu_utils::escape_quote_string;
use std::{
    env,
    fs::{self, create_dir, File},
    io::{Read, Write},
    os::unix,
    path::{Path, PathBuf},
};

fn main() {
    let task = Task {
        src: PathBuf::from(env::args_os().nth(1).expect("Three arguments expected")),
        name: env::args().nth(2).expect("Three arguments expected"),
        symlinkjoin: PathBuf::from(env::args_os().nth(3).expect("Three arguments expected")),
    };

    if let Err(e) = task.run() {
        eprintln!("ERROR: {}", e);
        for cause in e.chain().skip(1) {
            eprintln!("Cause: {}", cause);
        }
        std::process::exit(1);
    }
}

struct Task {
    src: PathBuf,
    name: String,
    symlinkjoin: PathBuf,
}

impl Task {
    fn run(&self) -> Result<()> {
        let src_string = self.src.to_string_lossy();
        println!(
            "Converting {} into package {}. Dependencies stored in {}.",
            src_string,
            self.name,
            self.symlinkjoin.to_string_lossy()
        );

        if self.src.is_file() {
            println!("{} is a file. Converting it to sole mod.nu", src_string);

            // Create output directory "build"
            create_dir("build").with_context(|| "Failed to create \"build\" directory")?;
            self.transform_nu_source(&self.src, Path::new("build/mod.nu"))?;
            self.link_nu_libs(Path::new("build"))?;
        } else if self.src.is_dir() {
            println!("{} is a file. Copying recursively", src_string);
            self.transform_dir(&self.src, Path::new("build"))?;
        } else {
            bail!(
                "{} is neither file nor directory or file is unreachable due to\
                permission error, broken symlink e.t.c.",
                src_string
            );
        }

        Ok(())
    }

    fn transform_dir(&self, src: &Path, target: &Path) -> Result<()> {
        struct CopyTask {
            src: PathBuf,
            dst: PathBuf,
            children_created: bool,
        }

        let mut work_stack = vec![CopyTask {
            src: src.to_path_buf(),
            dst: target.to_path_buf(),
            children_created: false,
        }];

        while let Some(CopyTask {
            src,
            dst,
            children_created,
        }) = work_stack.pop()
        {
            if children_created {
                self.link_nu_libs(&dst)?;
                continue;
            }

            work_stack.push(CopyTask {
                src: src.clone(),
                dst: dst.clone(),
                children_created: true,
            });

            fs::create_dir(&dst).with_context(|| {
                format!(
                    "Failed to create target directory {}",
                    dst.to_string_lossy()
                )
            })?;

            for entry in fs::read_dir(&src)? {
                let entry = entry?;

                if entry.path().is_dir() {
                    work_stack.push(CopyTask {
                        src: entry.path(),
                        dst: dst.join(entry.file_name()),
                        children_created: false,
                    });
                } else if entry
                    .path()
                    .extension()
                    .is_some_and(|extension| extension.eq("nu"))
                {
                    self.transform_nu_source(&entry.path(), &dst.join(entry.file_name()))
                        .with_context(|| {
                            format!(
                                "Failed to transform nu source {}",
                                entry.path().to_string_lossy()
                            )
                        })?;
                } else {
                    fs::copy(entry.path(), dst.join(entry.file_name())).with_context(|| {
                        format!(
                            "Failed to copy non-source file {}",
                            entry.path().to_string_lossy()
                        )
                    })?;
                }
            }
        }

        Ok(())
    }

    /// Link nu libs from dependencies to directory `target`
    fn link_nu_libs(&self, target: &Path) -> Result<()> {
        let nu_libs_dir = self.symlinkjoin.join("lib/nushell");

        if !nu_libs_dir.exists() {
            return Ok(());
        }

        let paths = fs::read_dir(&nu_libs_dir).with_context(|| {
            format!(
                "Failed to read contents of {}",
                nu_libs_dir.to_string_lossy()
            )
        })?;

        for path in paths {
            let path = path.with_context(|| {
                format!(
                    "Failed to read contents of {}",
                    nu_libs_dir.to_string_lossy()
                )
            })?;

            // If target directory already had directory with name
            // of this dependency leave as is
            if target.join(path.file_name()).exists() {
                continue;
            }

            unix::fs::symlink(path.path(), target.join(path.file_name())).with_context(|| {
                format!(
                    "Failed to create symlink for {} in {}",
                    path.path().to_string_lossy(),
                    target.to_string_lossy()
                )
            })?;
        }

        Ok(())
    }

    fn transform_nu_source(&self, src: &Path, dst: &Path) -> Result<()> {
        // Just copy file if no binary dependencies are used
        if !self.symlinkjoin.join("bin").exists() {
            fs::copy(src, dst).with_context(|| {
                format!(
                    "Failed to copy nu source file {} to {}",
                    src.to_string_lossy(),
                    dst.to_string_lossy()
                )
            })?;
            return Ok(());
        }

        let mut contents = Vec::new();
        File::open(src)
            .with_context(|| format!("Failed to open nu source file {}", src.to_string_lossy()))?
            .read_to_end(&mut contents)
            .with_context(|| format!("Failed to read nu source file {}", src.to_string_lossy()))?;

        let engine_state = get_engine_state();
        let mut working_set = StateWorkingSet::new(&engine_state);
        let parsed_block = parse(&mut working_set, None, &contents, true);

        // TODO: bail on (some) parse errors

        let search = Search::new(&contents);

        let export_defs: Vec<ExportDef> = search.in_block(&parsed_block).collect();

        let mut out = File::create_new(dst).with_context(|| {
            format!(
                "Failed to create new destination file {} while transforming nu source file {}",
                dst.to_string_lossy(),
                src.to_string_lossy()
            )
        })?;

        let used_functions = self
            .write_result(&mut out, &contents, &export_defs)
            .with_context(|| {
                format!(
                    "Failed to write patched functions for nu source file {}",
                    src.to_string_lossy()
                )
            })?;

        self.write_set_env_commands(&mut out, used_functions)
            .with_context(|| {
                format!(
                    "Failed to write helper functions for nu source file {}",
                    src.to_string_lossy()
                )
            })?;

        Ok(())
    }

    /// `__set_env` command injects binary dependencies into `$env.PATH`
    /// using symlinkJoinPath
    ///
    /// `__unset_env` finds and removes the first entry it meets
    /// there may be more than one if commands call each other. Then
    /// they should be popped one by one as a stack
    ///
    /// `__make_env` creates argument for with-env
    fn write_set_env_commands(
        &self,
        dst: &mut impl Write,
        used_functions: UsedFunctions,
    ) -> Result<()> {
        let bin_path = self.symlinkjoin.join("bin");
        let bin_path = bin_path.to_str().with_context(|| {
            format!(
                "Dependency path {} could not be converted to utf-8",
                self.symlinkjoin.to_string_lossy()
            )
        })?;

        let bin_path_string = escape_quote_string(bin_path);

        if used_functions.make_env {
            writeln!(
                dst,
                r"
def __make_env []: nothing -> record {{
  let path = {bin_path_string}
  {{PATH: [$path ...$env.PATH]}}
}}
",
            )?;
        }

        if used_functions.set_unset_env {
            writeln!(
                dst,
                r"
def --env __set_env []: any -> any {{
  let inp = $in
  let path = {bin_path_string}
  $env.PATH = [ $path ...$env.PATH ]
  $inp
}}

def --env __unset_env []: any -> any {{
  let inp = $in
  let idx = $env.PATH | enumerate
    | where item == {bin_path_string}
    | get index?.0?

  if $idx != null {{
    $env.PATH = ($env.PATH | drop nth $idx)
  }}
  $inp
}}",
            )?;
        }

        Ok(())
    }

    fn write_result(
        &self,
        dst: &mut impl Write,
        contents: &[u8],
        export_defs: &[ExportDef],
    ) -> Result<UsedFunctions> {
        const PREFIX: &[u8] = "{\nwith-env (__make_env) ".as_bytes();
        const SUFFIX: &[u8] = "\n}".as_bytes();
        const ENV_PREFIX: &[u8] = "{\n__set_env | do --env ".as_bytes();
        const ENV_SUFFIX: &[u8] = " | __unset_env\n}".as_bytes();

        let mut used_functions = UsedFunctions {
            set_unset_env: false,
            make_env: false,
        };

        let mut last_start = 0;
        for def in export_defs {
            dst.write_all(&contents[last_start..def.body.start])?;
            dst.write_all(if def.is_env {
                used_functions.set_unset_env = true;
                ENV_PREFIX
            } else {
                used_functions.make_env = true;
                PREFIX
            })?;
            dst.write_all(&contents[def.body.start..def.body.end])?;
            dst.write_all(if def.is_env { ENV_SUFFIX } else { SUFFIX })?;
            last_start = def.body.end;
        }

        dst.write_all(&contents[last_start..contents.len()])?;

        Ok(used_functions)
    }
}

struct UsedFunctions {
    /// `__set_env` `__unset_env` pair was used
    set_unset_env: bool,
    /// `__make_env` was used
    make_env: bool,
}

struct ExportDef {
    body: Span,
    is_env: bool,
}

struct Search<'a> {
    contents: &'a [u8],
}

impl<'a: 'b, 'b> Search<'a> {
    fn new(contents: &'a [u8]) -> Self {
        Self { contents }
    }

    fn in_block(&'a self, block: &'b Block) -> impl Iterator<Item = ExportDef> + 'b {
        block
            .pipelines
            .iter()
            .flat_map(|pipeline| self.in_pipeline(pipeline))
    }

    fn in_pipeline(&'a self, pipeline: &'b Pipeline) -> impl Iterator<Item = ExportDef> + 'b {
        pipeline
            .elements
            .iter()
            .filter_map(move |element| self.in_pipeline_element(element))
    }

    fn in_pipeline_element(&self, element: &PipelineElement) -> Option<ExportDef> {
        match &element.expr.expr {
            Expr::Call(call) => {
                if self.is_export_def(call.head) {
                    const BODY_INDEX: usize = 2;
                    const ENV_FLAG: &str = "env";

                    let is_env = call.get_named_arg(ENV_FLAG).is_some();
                    let body = call.positional_nth(BODY_INDEX)?.span;
                    Some(ExportDef { body, is_env })
                } else {
                    None
                }
            }
            _ => None,
        }
    }

    fn is_export_def(&self, span: Span) -> bool {
        const EXPORT_DEF_NAME: &str = "export def";
        &self.contents[span.start..span.end] == EXPORT_DEF_NAME.as_bytes()
    }
}

fn get_engine_state() -> EngineState {
    let mut engine_state = nu_cmd_lang::create_default_context();

    let pwd: String = env::current_dir()
        .map(|p| p.to_string_lossy().into())
        .unwrap_or_else(|_| "".into());
    engine_state.add_env_var("PWD".into(), Value::string(pwd, Span::unknown()));

    engine_state
}

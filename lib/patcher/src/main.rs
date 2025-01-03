use nu_parser::parse;
use nu_protocol::{
    ast::{Block, Expr, Pipeline, PipelineElement},
    engine::{EngineState, StateWorkingSet},
    Span, Value,
};
use nu_utils::escape_quote_string;
use std::{
    env,
    io::{self, Read, Write},
    path::MAIN_SEPARATOR,
};

fn main() {
    let mut contents = Vec::new();
    io::stdin()
        .read_to_end(&mut contents)
        .expect("Failed to read stdio");

    let engine_state = get_engine_state();
    let mut working_set = StateWorkingSet::new(&engine_state);
    let parsed_block = parse(&mut working_set, None, &contents, true);

    let search = Search::new(&contents);

    let export_defs: Vec<ExportDef> = search.in_block(&parsed_block).collect();
    let used_functions = write_result(&contents, &export_defs).expect("Failed to write to stdio");
    write_set_env_commands(used_functions);
}

/// `__set_env` command injects binary dependencies into `$env.PATH`
/// using symlinkJoinPath
///
/// `__unset_env` finds and removes the first entry it meets
/// there may be more than one if commands call each other. Then
/// they should be popped one by one as a stack
///
/// `__make_env` creates argument for with-env
fn write_set_env_commands(used_functions: UsedFunctions) {
    let symlinkjoin_path =
        env::var("symlinkjoin_path").expect("env variable symlinkjoin_path expected to be set");

    let bin_path = format!("{symlinkjoin_path}{MAIN_SEPARATOR}bin");
    let bin_path_string = escape_quote_string(&bin_path);

    if used_functions.make_env {
        println!(
            r"
def __make_env []: nothing -> record {{
  let path = {bin_path_string}
  {{PATH: [$path ...$env.PATH]}}
}}
"
        );
    }

    if used_functions.set_unset_env {
        println!(
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
        );
    }
}

struct UsedFunctions {
    /// `__set_env` `__unset_env` pair was used
    set_unset_env: bool,
    /// `__make_env` was used
    make_env: bool,
}

fn write_result(contents: &[u8], export_defs: &[ExportDef]) -> Result<UsedFunctions, io::Error> {
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
        io::stdout().write_all(&contents[last_start..def.body.start])?;
        io::stdout().write_all(if def.is_env {
            used_functions.set_unset_env = true;
            ENV_PREFIX
        } else {
            used_functions.make_env = true;
            PREFIX
        })?;
        io::stdout().write_all(&contents[def.body.start..def.body.end])?;
        io::stdout().write_all(if def.is_env { ENV_SUFFIX } else { SUFFIX })?;
        last_start = def.body.end;
    }

    io::stdout()
        .write_all(&contents[last_start..contents.len()])
        .map(|()| used_functions)
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

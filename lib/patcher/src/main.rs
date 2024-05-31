use std::{
    env,
    io::{self, Read, Write},
};

use nu_parser::parse;
use nu_protocol::{
    ast::{Block, Expr, Pipeline, PipelineElement},
    engine::{EngineState, StateWorkingSet},
    Span, Value,
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
    write_result(&contents, &export_defs).expect("Failed to write to stdio");
}

fn write_result(contents: &[u8], export_defs: &[ExportDef]) -> Result<(), io::Error> {
    const PREFIX: &[u8] = "{\nwith-env (__make_env) ".as_bytes();
    const SUFFIX: &[u8] = "\n}".as_bytes();
    const ENV_PREFIX: &[u8] = "{\n__set_env | do --env ".as_bytes();
    const ENV_SUFFIX: &[u8] = " | __unset_env\n}".as_bytes();

    let mut last_start = 0;
    for def in export_defs {
        io::stdout().write_all(&contents[last_start..def.body.start])?;
        io::stdout().write_all(if def.is_env { ENV_PREFIX } else { PREFIX })?;
        io::stdout().write_all(&contents[def.body.start..def.body.end])?;
        io::stdout().write_all(if def.is_env { ENV_SUFFIX } else { SUFFIX })?;
        last_start = def.body.end;
    }

    io::stdout().write_all(&contents[last_start..contents.len()])
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

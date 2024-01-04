use std::{env, path::PathBuf};

use nu_parser::parse;
use nu_protocol::{
    ast::{Block, Expr, Expression, Pipeline, PipelineElement},
    engine::{EngineState, StateWorkingSet},
    Span, Value,
};

fn main() {
    let args: Vec<String> = env::args().collect();
    let contents =
        std::fs::read(PathBuf::from(&args[1])).unwrap_or_else(|_| panic!("Could not open file"));

    let engine_state = get_engine_state();
    let mut working_set = StateWorkingSet::new(&engine_state);
    let parsed_block = parse(&mut working_set, Some(&args[1]), &contents, true);

    let search = Search::new(&contents);

    let export_defs: Vec<ExportDef> = search.in_block(&parsed_block).collect();

    for def in export_defs {
        println!(
            "name: {} is_env: {} body:\n```\n{}\n```\n",
            def.name,
            def.is_env,
            std::str::from_utf8(&contents[def.body.start..def.body.end])
                .expect("Invalid utf8 string")
        )
    }
}

struct ExportDef {
    name: String,
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
        match element {
            PipelineElement::Expression(
                _,
                Expression {
                    expr: Expr::Call(call),
                    ..
                },
            ) => {
                if self.is_export_def(call.head) {
                    const NAME_INDEX: usize = 0;
                    const BODY_INDEX: usize = 2;
                    const ENV_FLAG: &str = "env";
                    let name = call
                        .positional_nth(NAME_INDEX)
                        .and_then(Expression::as_string)
                        .unwrap_or_else(|| "".into());

                    let is_env = call.has_flag(ENV_FLAG);
                    let body = call.positional_nth(BODY_INDEX)?.span;
                    Some(ExportDef { name, body, is_env })
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

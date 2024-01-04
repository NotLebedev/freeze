use std::{env, path::PathBuf};

use nu_parser::parse;
use nu_protocol::{
    engine::{EngineState, StateWorkingSet},
    Span, Value,
};

fn main() {
    let args: Vec<String> = env::args().collect();
    let contents =
        std::fs::read(PathBuf::from(&args[1])).unwrap_or_else(|_| panic!("Could not open file"));

    let engine_state = get_engine_state();
    let mut working_set = StateWorkingSet::new(&engine_state);
    let parsed_block = parse(&mut working_set, None, &contents, false);

    for pipeline in &parsed_block.pipelines {
        println!("pipeline:\n{:?}\n", &pipeline);
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

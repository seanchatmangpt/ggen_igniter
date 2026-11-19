# Root Justfile. Lane modules live under justfile.d/ (import? tolerates absence).
import? 'justfile.d/10-sjira.just'

default:
    @just --list

#!/usr/bin/env python3
"""Format an already-parsed XML tree without importing an XML parser."""

from __future__ import annotations


def indent_tree(tree, space: str = "  ") -> None:
    """Add deterministic whitespace indentation to an in-memory XML tree."""
    _indent_element(tree.getroot(), level=0, space=space)


def _indent_element(element, *, level: int, space: str) -> None:
    current_indent = "\n" + (space * level)
    child_indent = current_indent + space
    children = list(element)

    if children:
        if not element.text or not element.text.strip():
            element.text = child_indent
        for child in children:
            _indent_element(child, level=level + 1, space=space)
        last_child = children[-1]
        if not last_child.tail or not last_child.tail.strip():
            last_child.tail = current_indent

    if level and (not element.tail or not element.tail.strip()):
        element.tail = current_indent

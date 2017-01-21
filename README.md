# pastmasterparser
A Ruby parser for the Past Masters website. Generates a PDF book of the gathered HTML websites

# Status

- As of now, the project *only* generates PDFs of Dewey's Complete Works. I'm pretty sure that the file structure for the other texts on the website is relevantly similar so that an adaptation should be easy to do, however.

# Installation

- Requirements: 
    - A functioning pandoc and XeLaTeX installation
    - Proxy and Login-free access to the past masters website. I am not providing tools to steal content, merely to lay it out in a PDF-reader and annotation-friendly way.
- A clone of the repo

# Usage

- Run `ruby DeweyParser.rb #{ew|mw|lw} #{volume}` where the first parameter indicates the Early, Middle, or Late Works and the second parameter indicates the Volume
- Profit

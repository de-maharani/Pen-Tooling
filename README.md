# Pen-Tooling

A collection of tools built for easy testing, use, and incorporation by red-teamers as utility solutions for "low-hanging fruit" problems and other friction that often arise over the course of a penetration test.

Rather than low-level code, these proudly orchestrate workflows leveraging existing tooling from wonderful creations by the community. 

## 🧰 The Toolkit

| Tool | Language | Description |
| :--- | :--- | :--- |
| [**Downy**](./Downy/) | Python | a threaded HTTP file receiver for downloading files via target-push |
| [**CorP**](./CorP/) | CMD & PowerShell | returns whether the Windows target is using CMD or Powershell |
| [**NameFile**](./NameFile/) | Bash | extracts names and comments from all possible readable local files |
| [**FileNamer**](./FileNamer/) | Bash | extracts names and comments from local files for wordlists |
| [**WebHead**](./WebHead/) | Bash | mines a list of live URLs for names and emails to spray with |
| [**Paramecia**](./Paramecia/) | Bash | a multi-stage web parameter discovery and hidden-param fuzzer |
| [**CRONY**](./CRONY/) | Bash | finds non-default cron scripts and checks inside for writable referenced paths |
| [**GTFObuddy**](./GTFObuddy/) | Bash | quickly and easily cross-references SUID and capability findings against GTFOBins |
| [**Unquoth**](./Unquoth/) | PowerShell | tests writability for the entire tree of an unquoted service path |

## 💡 Usage
Click into any tool's folder to view its specific documentation, required dependencies, and configuration steps. Most tools require little more than standard bash/Python environments.

## 🙏 Acknowledgements

These tools stand on the shoulders of giants. Endless thanks to the creators and maintainers of the following projects, which are heavily utilized (or entirely depended upon) by the workflows in this repository:

- [**GTFOBins**](https://gtfobins.github.io/) — For the essential SUID and capability exploit data.
- [**username-anarchy**](https://github.com/urbanadventurer/username-anarchy) — For username permutation generation.
- [**cewl**](https://github.com/digininja/CeWL) — For web crawling and wordlist generation.
- [**x8**](https://github.com/Sh1Yo/x8) — For hidden parameter discovery.
- [**ffuf**](https://github.com/ffuf/ffuf) — For fast web fuzzing.
- [**SecLists**](https://github.com/danielmiessler/SecLists) — For the parameter-name wordlists used during fuzzing.

## 🤝 Feedback

**Let me know if you used any of my tools; I'm interested to hear what you think!** 

## ⚠️ Disclaimer

These tools are provided for **authorized security testing and educational use only**. The author assumes no liability for misuse or for any damage caused by these tools. Always ensure you have explicit, written permission before testing any target.

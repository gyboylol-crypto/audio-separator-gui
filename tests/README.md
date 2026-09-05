# Tests

See [TESTING.md](../TESTING.md) for verification scope and limitations.

Run unit tests from the project root with the project-local Python:

```powershell
.\.runtime\python\python.exe -X utf8 -m unittest discover -s tests -v
```

Integration and live-progress tests require installed dependencies and models.
Use only audio you are authorized to process. Do not commit test audio or logs.

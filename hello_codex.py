"""一个可以在 VS Code 中打开、编辑和运行的 Python 示例。"""


def greet(name: str) -> str:
    return f"你好，{name}！这是在 Codex 中创建的 Python 文件。"


def main() -> None:
    print(greet("朋友"))
    numbers = [1, 2, 3, 4, 5]
    print(f"数字列表：{numbers}")
    print(f"总和：{sum(numbers)}")
    print("试着在 VS Code 中修改名字，然后再次运行。")
    print('第三版？')


if __name__ == "__main__":
    main()
    

Save Manager for Balatro, macOS only

## Usage

# Build
Run and copy the app (GUI or Executable) from Xcode/Vscode, or:
```
git clone https://github.com/miku1958/Balatro.antihypertensive
cd Balatro.antihypertensive
swift build
cd .build/arm64-apple-macosx/debug
```


# GUI
1. Select the save forlder on first boot

you can open the C drive in Whisky
<img width="1012" alt="Screenshot 2024-02-25 at 16 27 43" src="https://github.com/miku1958/Balatro.antihypertensive/assets/24806909/38fab228-ea37-4cc0-8183-d738c845e967">
Then find the save folder under  `drive_c/users/crossover/AppData/Roaming/Balatro`

2. After the game is saved, a new item will appear in the UI
<img width="1012" alt="image" src="https://github.com/miku1958/Balatro.antihypertensive/assets/24806909/c18593f3-8f83-4e05-a2d6-fb100f71cb0a">


# Executable
1. If this is your first boot, add the save folder as a parameter: `Executable /Users/xxx/Library/Containers/com.isaacmarovitz.Whisky/Bottles/yyyy/drive_c/users/crossover/AppData/Roaming/Balatro`
2. The executable file will back up save files automatically.
3. Manually restore the save file.

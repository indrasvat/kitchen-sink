# /// script
# requires-python = ">=3.8"
# dependencies = [
#   "pygame",
# ]
# ///

import pygame
import random
import math
from pygame import mixer

# Initialize Pygame and mixer
pygame.init()
mixer.init()

# Screen settings
WIDTH = 800
HEIGHT = 600
screen = pygame.display.set_mode((WIDTH, HEIGHT))
pygame.display.set_caption("Retro Space Wars")

# Retro Colors
BLACK = (0, 0, 0)
WHITE = (255, 255, 255)
RED = (255, 87, 87)
GREEN = (87, 255, 87)
BLUE = (87, 87, 255)
YELLOW = (255, 255, 87)

# Font
font = pygame.font.Font(None, 36)

# Sound effects (commented out—download chiptune files and uncomment)
# shoot_sound = mixer.Sound("path/to/shoot.wav")
# explosion_sound = mixer.Sound("path/to/explosion.wav")
# level_up_sound = mixer.Sound("path/to/level_up.wav")

class Player:
    def __init__(self, x, y):
        self.image = pygame.Surface((32, 32))  # Smaller, pixelated player
        self.image.fill(BLUE)
        self.rect = self.image.get_rect()
        self.rect.x = x
        self.rect.y = y
        self.speed = 5
        self.lives = 3

    def move(self):
        keys = pygame.key.get_pressed()
        if keys[pygame.K_LEFT] and self.rect.x > 0:
            self.rect.x -= self.speed
        if keys[pygame.K_RIGHT] and self.rect.x < WIDTH - self.rect.width:
            self.rect.x += self.speed

    def draw(self, surface):
        surface.blit(self.image, self.rect)

class Bullet:
    def __init__(self, x, y):
        self.image = pygame.Surface((8, 16))  # Thin, fast bullet
        self.image.fill(YELLOW)
        self.rect = self.image.get_rect()
        self.rect.x = x
        self.rect.y = y
        self.speed = 7

    def update(self):
        self.rect.y -= self.speed
        return self.rect.y < 0

    def draw(self, surface):
        surface.blit(self.image, self.rect)

class Enemy:
    def __init__(self, type, speed_mult):
        sizes = [(24, 24), (32, 32), (40, 40)]  # Small, medium, large
        speeds = [2, 3, 4]
        self.image = pygame.Surface(sizes[type])
        colors = [RED, (255, 127, 127), (255, 63, 63)]  # Varying shades of red
        self.image.fill(colors[type])
        self.rect = self.image.get_rect()
        self.rect.x = random.randint(0, WIDTH - self.rect.width)
        self.rect.y = -self.rect.height
        self.speed = speeds[type] * speed_mult  # Use the passed speed_mult
        self.type = type

    def update(self):
        self.rect.y += self.speed
        return self.rect.y > HEIGHT

    def draw(self, surface):
        surface.blit(self.image, self.rect)

class Game:
    def __init__(self):
        self.player = Player(WIDTH // 2, HEIGHT - 60)
        self.bullets = []
        self.enemies = []
        self.score = 0
        self.current_level = 0
        self.levels = [
            {"enemy_count": 5, "speed_mult": 1, "spawn_rate": 30},  # Reduced spawn_rate for testing
            {"enemy_count": 10, "speed_mult": 1.5, "spawn_rate": 20},
            {"enemy_count": 15, "speed_mult": 2, "spawn_rate": 15}
        ]
        self.enemies_to_spawn = self.levels[self.current_level]["enemy_count"]
        self.spawn_timer = 0
        self.clock = pygame.time.Clock()

    def spawn_enemy(self):
        if self.enemies_to_spawn > 0 and random.randint(1, self.levels[self.current_level]["spawn_rate"]) == 1:
            enemy = Enemy(random.randint(0, 2), self.levels[self.current_level]["speed_mult"])  # Pass speed_mult
            self.enemies.append(enemy)
            self.enemies_to_spawn -= 1
            print(f"Spawned enemy, remaining: {self.enemies_to_spawn}")  # Debug print

    def handle_input(self):
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                return False
            elif event.type == pygame.KEYDOWN and event.key == pygame.K_SPACE and len(self.bullets) < 5:
                bullet = Bullet(self.player.rect.x + self.player.rect.width // 2 - 4, self.player.rect.y)
                self.bullets.append(bullet)
                # Uncomment and set the correct path if you have a shoot sound file
                # shoot_sound.play()
        return True

    def update(self):
        self.player.move()

        # Update bullets
        self.bullets = [b for b in self.bullets if not b.update()]

        # Update enemies
        self.enemies = [e for e in self.enemies if not e.update()]
        if not self.enemies and self.enemies_to_spawn == 0:
            self.current_level += 1
            if self.current_level < len(self.levels):
                self.enemies_to_spawn = self.levels[self.current_level]["enemy_count"]
                # Uncomment and set the correct path if you have a level up sound file
                # level_up_sound.play()
            else:
                return False

        # Check collisions
        for bullet in self.bullets[:]:
            for enemy in self.enemies[:]:
                if bullet.rect.colliderect(enemy.rect):
                    self.bullets.remove(bullet)
                    self.enemies.remove(enemy)
                    self.score += 10 * (enemy.type + 1)
                    # Uncomment and set the correct path if you have an explosion sound file
                    # explosion_sound.play()

        # Spawn enemies
        self.spawn_timer += 1
        if self.spawn_timer >= self.levels[self.current_level]["spawn_rate"]:
            self.spawn_enemy()
            self.spawn_timer = 0

        # Check player lives
        if any(e.update() for e in self.enemies if e.rect.y > HEIGHT):
            self.player.lives -= 1
            # Uncomment and set the correct path if you have an explosion sound file
            # explosion_sound.play()
            self.enemies = [e for e in self.enemies if e.rect.y <= HEIGHT]

        if self.player.lives <= 0:
            return False

        return True

    def draw(self):
        screen.fill(BLACK)
        self.player.draw(screen)
        for bullet in self.bullets:
            bullet.draw(screen)
        for enemy in self.enemies:
            enemy.draw(screen)
        self.draw_hud()

    def draw_hud(self):
        draw_text(f"Score: {self.score}", WHITE, 10, 10)
        draw_text(f"Lives: {self.player.lives}", WHITE, 10, 40)
        draw_text(f"Level: {self.current_level + 1}", WHITE, 10, 70)

    def run(self):
        running = True
        while running:
            running = self.handle_input()
            if not running:
                break

            running = self.update()
            if not running:
                if self.current_level >= len(self.levels):
                    draw_text("You Won!", WHITE, WIDTH//2 - 50, HEIGHT//2)
                else:
                    draw_text("Game Over!", WHITE, WIDTH//2 - 50, HEIGHT//2)
                pygame.display.flip()
                pygame.time.wait(2000)
                break

            self.draw()
            pygame.display.flip()
            self.clock.tick(60)

        pygame.quit()

def draw_text(text, color, x, y):
    text_surface = font.render(text, True, color)
    screen.blit(text_surface, (x, y))

if __name__ == "__main__":
    game = Game()
    game.run()
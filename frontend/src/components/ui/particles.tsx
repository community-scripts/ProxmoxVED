"use client";

import { cn } from "@/lib/utils";
import React, { useEffect, useRef, useState, useCallback } from "react";

// Custom Hook für Mausposition
function useMousePosition() {
  const [mousePosition, setMousePosition] = useState({ x: 0, y: 0 });

  useEffect(() => {
    const handleMouseMove = (event: MouseEvent) => {
      setMousePosition({ x: event.clientX, y: event.clientY });
    };

    window.addEventListener("mousemove", handleMouseMove);
    return () => window.removeEventListener("mousemove", handleMouseMove);
  }, []);

  return mousePosition;
}

// Umwandlung von HEX in RGB
function hexToRgb(hex: string): number[] {
  hex = hex.replace("#", "");
  if (hex.length === 3) {
    hex = hex.split("").map((char) => char + char).join("");
  }
  return [
    parseInt(hex.substring(0, 2), 16),
    parseInt(hex.substring(2, 4), 16),
    parseInt(hex.substring(4, 6), 16),
  ];
}

// Partikel-Interface
interface Particle {
  x: number;
  y: number;
  translateX: number;
  translateY: number;
  size: number;
  alpha: number;
  targetAlpha: number;
  dx: number;
  dy: number;
  magnetism: number;
}

interface ParticlesProps {
  className?: string;
  quantity?: number;
  staticity?: number;
  ease?: number;
  size?: number;
  refresh?: boolean;
  color?: string;
  vx?: number;
  vy?: number;
}

const Particles: React.FC<ParticlesProps> = ({
  className = "",
  quantity = 100,
  staticity = 50,
  ease = 50,
  size = 0.4,
  refresh = false,
  color = "#ffffff",
  vx = 0,
  vy = 0,
}) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const canvasContainerRef = useRef<HTMLDivElement>(null);
  const context = useRef<CanvasRenderingContext2D | null>(null);
  const circles = useRef<Particle[]>([]);
  const animationFrameRef = useRef<number | null>(null);
  const mousePosition = useMousePosition();
  const mouse = useRef({ x: 0, y: 0 });
  const canvasSize = useRef({ w: 0, h: 0 });
  const dpr = typeof window !== "undefined" ? window.devicePixelRatio : 1;
  const rgb = hexToRgb(color);

  const resizeCanvas = useCallback(() => {
    if (!canvasContainerRef.current || !canvasRef.current) return;
    const { offsetWidth: w, offsetHeight: h } = canvasContainerRef.current;
    Object.assign(canvasSize.current, { w, h });

    canvasRef.current.width = w * dpr;
    canvasRef.current.height = h * dpr;
    canvasRef.current.style.width = `${w}px`;
    canvasRef.current.style.height = `${h}px`;

    if (context.current) {
      context.current.scale(dpr, dpr);
    }

    circles.current = Array.from({ length: quantity }, createParticle);
  }, [quantity]);

  const createParticle = (): Particle => ({
    x: Math.random() * canvasSize.current.w,
    y: Math.random() * canvasSize.current.h,
    translateX: 0,
    translateY: 0,
    size: Math.random() * 2 + size,
    alpha: 0,
    targetAlpha: Math.random() * 0.6 + 0.1,
    dx: (Math.random() - 0.5) * 0.1,
    dy: (Math.random() - 0.5) * 0.1,
    magnetism: 0.1 + Math.random() * 4,
  });

  const clearCanvas = () => {
    context.current?.clearRect(0, 0, canvasSize.current.w, canvasSize.current.h);
  };

  const drawParticle = (particle: Particle) => {
    if (!context.current) return;
    const { x, y, translateX, translateY, size, alpha } = particle;
    context.current.save();
    context.current.translate(translateX, translateY);
    context.current.beginPath();
    context.current.arc(x, y, size, 0, 2 * Math.PI);
    context.current.fillStyle = `rgba(${rgb.join(",")}, ${alpha})`;
    context.current.fill();
    context.current.restore();
  };

  const animateParticles = () => {
    clearCanvas();
    circles.current.forEach((particle) => {
      particle.x += particle.dx + vx;
      particle.y += particle.dy + vy;
      particle.translateX += (mouse.current.x / (staticity / particle.magnetism) - particle.translateX) / ease;
      particle.translateY += (mouse.current.y / (staticity / particle.magnetism) - particle.translateY) / ease;
      particle.alpha = Math.min(particle.alpha + 0.02, particle.targetAlpha);

      drawParticle(particle);

      if (
        particle.x < -particle.size ||
        particle.x > canvasSize.current.w + particle.size ||
        particle.y < -particle.size ||
        particle.y > canvasSize.current.h + particle.size
      ) {
        Object.assign(particle, createParticle());
      }
    });
    animationFrameRef.current = requestAnimationFrame(animateParticles);
  };

  useEffect(() => {
    if (canvasRef.current) {
      context.current = canvasRef.current.getContext("2d");
      resizeCanvas();
      animateParticles();
      window.addEventListener("resize", resizeCanvas);
    }
    return () => {
      if (animationFrameRef.current) {
        cancelAnimationFrame(animationFrameRef.current);
      }
      window.removeEventListener("resize", resizeCanvas);
    };
  }, [resizeCanvas, refresh]);

  useEffect(() => {
    if (!canvasRef.current) return;
    const rect = canvasRef.current.getBoundingClientRect();
    const { w, h } = canvasSize.current;
    const x = mousePosition.x - rect.left - w / 2;
    const y = mousePosition.y - rect.top - h / 2;
    if (x < w / 2 && x > -w / 2 && y < h / 2 && y > -h / 2) {
      mouse.current.x = x;
      mouse.current.y = y;
    }
  }, [mousePosition]);

  return (
    <div className={cn("pointer-events-none", className)} ref={canvasContainerRef} aria-hidden="true">
      <canvas ref={canvasRef} className="size-full" />
    </div>
  );
};

export default Particles;

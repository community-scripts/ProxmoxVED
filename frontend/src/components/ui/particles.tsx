"use client";

import React, { useEffect, useRef, useState, useCallback } from "react";
import { cn } from "@/lib/utils";

function useMousePosition() {
    const [mousePosition, setMousePosition] = useState({ x: -9999, y: -9999 });

    useEffect(() => {
        const handleMouseMove = (event: MouseEvent) => {
            setMousePosition({ x: event.clientX, y: event.clientY });
        };

        window.addEventListener("mousemove", handleMouseMove);
        return () => window.removeEventListener("mousemove", handleMouseMove);
    }, []);

    return mousePosition;
}

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
    color: string;
}

interface ParticlesProps {
    className?: string;
    quantity?: number;
    staticity?: number;
    ease?: number;
    size?: number;
    refresh?: boolean;
    vx?: number;
    vy?: number;
    color?: string;
}

const Particles: React.FC<ParticlesProps> = ({
    className = "",
    quantity = 400,
    staticity = 50,
    ease = 25,
    size = 0.8,
    refresh = false,
    vx = 0.1,
    vy = 0.1,
    color = "#ff00ff",
}) => {
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const canvasContainerRef = useRef<HTMLDivElement>(null);
    const context = useRef<CanvasRenderingContext2D | null>(null);
    const circles = useRef<Particle[]>([]);
    const mousePosition = useMousePosition();
    const mouse = useRef({ x: 0, y: 0 });
    const canvasSize = useRef({ w: 0, h: 0 });
    const dpr = typeof window !== "undefined" ? window.devicePixelRatio : 1;

    const getRandomColor = () => {
        const colors = ["#ff00ff", "#00ffff", "#ff0099", "#0099ff", "#cc00ff", "#00ffcc"];
        return colors[Math.floor(Math.random() * colors.length)];
    };

    const animationFrameRef = useRef<number | null>(null);
    const resizeCanvas = useCallback(() => {
        if (!canvasContainerRef.current || !canvasRef.current) return;

        canvasSize.current.w = canvasContainerRef.current.offsetWidth;
        canvasSize.current.h = canvasContainerRef.current.offsetHeight;
        const { w, h } = canvasSize.current;

        canvasRef.current.width = w * dpr;
        canvasRef.current.height = h * dpr;
        canvasRef.current.style.width = `${w}px`;
        canvasRef.current.style.height = `${h}px`;

        context.current = canvasRef.current.getContext("2d");
        if (context.current) {
            context.current.scale(dpr, dpr);
        }

        circles.current = Array.from({ length: quantity }, createParticle);
    }, [dpr, quantity]);

    const createParticle = (): Particle => ({
        x: Math.random() * canvasSize.current.w,
        y: Math.random() * canvasSize.current.h,
        translateX: 0,
        translateY: 0,
        size: Math.random() * 2 + size,
        alpha: 0,
        targetAlpha: Math.random() * 0.8 + 0.2,
        dx: (Math.random() - 0.5) * Math.random() * 0.4,
        dy: (Math.random() - 0.5) * Math.random() * 0.4,
        magnetism: 0.5 + Math.random() * 3,
        color: getRandomColor(),
    });

    const clearCanvas = () => {
        if (context.current) {
            context.current.fillStyle = "rgba(10, 10, 30, 0.2)";
            context.current.fillRect(0, 0, canvasSize.current.w, canvasSize.current.h);
        }
    };

    const drawParticle = (particle: Particle) => {
        if (!context.current) return;

        context.current.save();
        context.current.translate(particle.translateX, particle.translateY);
        context.current.beginPath();
        context.current.arc(particle.x, particle.y, particle.size, 0, 2 * Math.PI);

        context.current.fillStyle = particle.color;
        context.current.shadowColor = particle.color;
        context.current.shadowBlur = 15;
        context.current.fill();
        context.current.restore();
    };

    const connectParticles = () => {
        if (!context.current) return;

        const maxDistance = 120;
        circles.current.forEach((p1, i) => {
            for (let j = i + 1; j < circles.current.length; j++) {
                const p2 = circles.current[j];
                const dx = p1.x - p2.x;
                const dy = p1.y - p2.y;
                const distance = Math.sqrt(dx * dx + dy * dy);

                if (distance < maxDistance) {
                    const opacity = 1 - distance / maxDistance;
                    context.current.strokeStyle = `rgba(255, 0, 255, ${opacity * 0.8})`;
                    context.current.lineWidth = 0.6;

                    context.current.beginPath();
                    context.current.moveTo(p1.x, p1.y);
                    context.current.lineTo(p2.x, p2.y);
                    context.current.stroke();
                }
            }
        });
    };

    const animateParticles = useCallback(() => {
        clearCanvas();
        circles.current.forEach((particle) => {
            particle.size = Math.max(particle.size - 0.01, 0.8);

            particle.x += particle.dx + vx;
            particle.y += particle.dy + vy;

            if (
                particle.x < -particle.size ||
                particle.x > canvasSize.current.w + particle.size ||
                particle.y < -particle.size ||
                particle.y > canvasSize.current.h + particle.size
            ) {
                Object.assign(particle, createParticle());
            }

            drawParticle(particle);
        });

        connectParticles();

        if (!animationFrameRef.current) {
            animationFrameRef.current = requestAnimationFrame(animateParticles);
        }
    }, [vx, vy, staticity, ease]);




    useEffect(() => {
        resizeCanvas();

        const loop = () => {
            animateParticles();
            animationFrameRef.current = requestAnimationFrame(loop);
        };

        animationFrameRef.current = requestAnimationFrame(loop);

        const handleResize = () => resizeCanvas();
        window.addEventListener("resize", handleResize);

        return () => {
            window.removeEventListener("resize", handleResize);
            if (animationFrameRef.current) {
                cancelAnimationFrame(animationFrameRef.current);
            }
        };
    }, [animateParticles]);



    return <div className={cn("pointer-events-none bg-black", className)} ref={canvasContainerRef}><canvas ref={canvasRef} className="size-full" /></div>;
};

export default Particles;

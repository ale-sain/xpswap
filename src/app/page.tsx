"use client"
import { useEffect, useState } from "react";
import { Hammer } from "lucide-react";

export default function Home() {
  const [isAnimating, setIsAnimating] = useState(false);

  useEffect(() => {
    const timer = setTimeout(() => {
      setIsAnimating(true);
    }, 1000);

    return () => clearTimeout(timer);
  }, []);

  return (
    <div className="flex items-center justify-center min-h-screen bg-gray-800">
      <div
        className={`p-8 text-center text-white text-xl font-semibold ${
          isAnimating ? "animate-pulse" : ""
        }`}
      >
        <div className="mb-4">
          <div className="flex justify-center items-center gap-4">
            <Hammer
              className={`text-white ${isAnimating ? "animate-bounce" : ""}`}
              size={70}
            />
          </div>
        </div>
        <h1>
          The site is under construction... <br />
          Come back soon!
        </h1>
      </div>
    </div>
  );
}


